#!/usr/bin/env bash
# runners.sh: keeps a few self-hosted GitHub runners waiting for jobs, each one good for a single job
# (chapter 8, tier 3). Run by nwn-runners.service, as root, on the control host or a build machine: never on the
# game host.
#
#   runners.sh            run every slot, forever (what the service does)
#   runners.sh slot 2     run slot 2 only, in the foreground, for trying it out
#   runners.sh status     which slots have a runner, and what GitHub sees
#   runners.sh stop       stop every slot's containers (the service's stop does this too)
#
# Each slot, over and over:
#   1. asks GitHub for a one-time runner registration (a "just-in-time" configuration), with the token in
#      TOKEN_FILE. The token never reaches the runner: the registration is good for one runner, one job;
#   2. starts a Docker of the slot's own (Docker in Docker), with its own images, containers and networks, held to
#      the slot's share of the cores and memory: the test server and its database run in there;
#   3. starts the runner, in a container from nwn-runner (Dockerfile), which takes one job and exits;
#   4. throws both away, with the job's files, and starts again.
# So every job starts on a clean machine, as on GitHub's own, and nothing a job leaves can reach the next one,
# except the slot's downloaded images (kept to save time) and the shared caches below.
#
# Settings: /etc/nwn-runners/runners.conf (runners.conf.example).
set -euo pipefail
CONF=${RUNNERS_CONF:-/etc/nwn-runners/runners.conf}
# shellcheck source=/dev/null
. "$CONF"
: "${REPO:?set REPO=owner/name in $CONF}" "${TOKEN_FILE:?set TOKEN_FILE in $CONF}"
SLOTS=${SLOTS:-2} LABELS=${LABELS:-nwn} CPUS=${CPUS:-1.5} MEMORY=${MEMORY:-3g}
IMAGE=${IMAGE:-nwn-runner:2.338.2} DIND_IMAGE=${DIND_IMAGE:-docker:29.9.3-dind}
CACHE_DIR=${CACHE_DIR:-/srv/nwn-runners/cache} GAME_DIR=${GAME_DIR:-}
GITHUB_API=${GITHUB_API:-https://api.github.com} NAME_PREFIX=${NAME_PREFIX:-$(hostname -s)}
# The runner image's docker group, so the runner user can use the slot's Docker.
DOCKER_GID=123
# Made by "stop", so a slot whose runner was just removed doesn't register a new one on its way out.
STOPPING=/run/nwn-runners.stopping

say() { echo "slot ${1}: ${*:2}"; }

# A one-time registration for one ephemeral runner: the "encoded_jit_config" GitHub hands back.
jit_config() {
  local name=$1 labels
  # A runner registered this way has only the labels it is given: "self-hosted" is not added for you.
  labels=$(jq -cn --arg l "$LABELS" '["self-hosted", "linux", "x64"] + ($l | split(","))')
  curl -fsS -X POST -H @<(printf 'Authorization: Bearer %s\n' "$(cat "$TOKEN_FILE")") \
    -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' \
    "$GITHUB_API/repos/$REPO/actions/runners/generate-jitconfig" \
    -d "$(jq -cn --arg n "$name" --argjson l "$labels" '{name: $n, runner_group_id: 1, labels: $l, work_folder: "_work"}')" |
    jq -er .encoded_jit_config
}

clean_slot() {
  local s=$1
  # Politely first: a runner told to stop tells GitHub it is going, so no job is handed to a runner that is gone.
  docker stop -t 20 "runner-$s" > /dev/null 2>&1 || true
  docker rm -f "runner-$s" "runner-$s-docker" > /dev/null 2>&1 || true
  docker volume rm -f "runner-$s-work" "runner-$s-sock" > /dev/null 2>&1 || true
  docker network rm "runner-$s" > /dev/null 2>&1 || true
}

one_job() {
  local s=$1 name config mounts=()
  clean_slot "$s"
  name="$NAME_PREFIX-$s-$(date +%s)"
  config=$(jit_config "$name") || { say "$s" "no registration from GitHub (is the token right? can this machine reach GitHub?); trying again in a minute"; sleep 60; return; }
  # The job's files live in a volume both containers see at the same path, so the paths a job hands its Docker
  # (tests/compose.yaml's folders) mean the same thing in both. The caches are shared by every slot, the same way.
  mounts=(-v "runner-$s-work:/home/runner/_work" -v "$CACHE_DIR:$CACHE_DIR")
  [ -z "$GAME_DIR" ] || mounts+=(-v "$GAME_DIR:$GAME_DIR:ro")
  docker network create "runner-$s" > /dev/null
  docker volume create "runner-$s-images" > /dev/null
  # A new volume belongs to root; the runner works as its own user.
  docker run --rm --user 0 --entrypoint chown -v "runner-$s-work:/w" "$IMAGE" 1001:1001 /w
  # Docker in Docker needs --privileged: a job on this runner can take over this machine. That is why it only
  # ever runs your own team's code (the hook refuses forks) and never sits on the game host.
  docker run -d --name "runner-$s-docker" --privileged --network "runner-$s" \
    --cpus "$CPUS" --memory "$MEMORY" \
    -v "runner-$s-images:/var/lib/docker" -v "runner-$s-sock:/run/dind" "${mounts[@]}" \
    "$DIND_IMAGE" dockerd --host=unix:///run/dind/docker.sock --group="$DOCKER_GID" > /dev/null
  for _ in $(seq 30); do
    docker exec "runner-$s-docker" docker -H unix:///run/dind/docker.sock info > /dev/null 2>&1 && break
    sleep 1
  done
  # Last job's leftovers, but not its images: those are kept, so each job doesn't download the NWNX image again.
  docker exec "runner-$s-docker" sh -c 'export DOCKER_HOST=unix:///run/dind/docker.sock;
    docker ps -aq | xargs -r docker rm -f; docker volume prune -af; docker network prune -f' > /dev/null 2>&1 || true
  say "$s" "runner $name waiting for a job"
  docker run --rm --name "runner-$s" --network "runner-$s" --cpus 1 --memory 1g \
    -e DOCKER_HOST=unix:///run/dind/docker.sock -e NWN_CONTENT_CACHE="$CACHE_DIR/nwsync" \
    -e RUNNER_REPOS="$REPO" ${GAME_DIR:+-e NWN_GAME_DIR="$GAME_DIR"} \
    -v "runner-$s-sock:/run/dind" "${mounts[@]}" \
    "$IMAGE" ./run.sh --jitconfig "$config" > "/var/log/nwn-runners/slot-$s.log" 2>&1 || true
  say "$s" "runner $name finished: $(grep -E 'completed with result|Job .* completed' "/var/log/nwn-runners/slot-$s.log" | tail -n 1 || echo 'no job')"
  clean_slot "$s"
}

slot() {
  local s=$1
  trap 'clean_slot '"$s"'; exit 0' TERM INT
  while [ ! -e "$STOPPING" ]; do one_job "$s"; done
}

case ${1:-all} in
  all)
    rm -f "$STOPPING"
    mkdir -p "$CACHE_DIR/nwsync" /var/log/nwn-runners
    # The runner user (uid 1001 in the image) writes the content cache.
    chown 1001:1001 "$CACHE_DIR/nwsync"
    # Old content versions out of the cache: a version not used for 14 days is not coming back.
    find "$CACHE_DIR/nwsync" -mindepth 1 -maxdepth 1 -type d -atime +14 -exec rm -rf {} + 2>/dev/null || true
    pids=()
    for s in $(seq "$SLOTS"); do slot "$s" & pids+=($!); done
    trap 'kill "${pids[@]}" 2>/dev/null; wait; exit 0' TERM INT
    wait ;;
  slot) rm -f "$STOPPING"; mkdir -p "$CACHE_DIR/nwsync" /var/log/nwn-runners; slot "${2:?which slot}" ;;
  status)
    for s in $(seq "$SLOTS"); do
      printf 'slot %s: %s\n' "$s" "$(docker ps --filter "name=^runner-$s$" --format '{{.Status}}' | grep . || echo 'no runner')"
    done
    curl -fsS -H @<(printf 'Authorization: Bearer %s\n' "$(cat "$TOKEN_FILE")") "$GITHUB_API/repos/$REPO/actions/runners" |
      jq -r '.runners[] | "\(.name) \(.status) busy=\(.busy) \([.labels[].name] | join(","))"' ;;
  stop)
    touch "$STOPPING"
    # A waiting runner goes at once; one in the middle of a job finishes it first, for up to DRAIN_SECONDS. Idle
    # slots are emptied first, so they can't take a new job while a busy one finishes.
    busy() { grep -E 'Listening for Jobs|Running job:|completed with result' "/var/log/nwn-runners/slot-$1.log" 2>/dev/null |
      tail -n 1 | grep -q 'Running job:' && [ -n "$(docker ps -q --filter "name=^runner-$1$")" ]; }
    left=$(seq "$SLOTS") end=$((SECONDS + ${DRAIN_SECONDS:-1200}))
    while [ -n "$left" ]; do
      still=
      for s in $left; do
        if busy "$s" && [ $SECONDS -lt $end ]; then still="$still $s"; else clean_slot "$s"; fi
      done
      left=$still
      [ -z "$left" ] || { echo "waiting for the job on slot(s)$left to finish"; sleep 5; }
    done
    # A runner stopped while it waited stays listed on GitHub as offline: remove ours.
    api() { curl -fsS -X "$1" -H @<(printf 'Authorization: Bearer %s\n' "$(cat "$TOKEN_FILE")") "$GITHUB_API/repos/$REPO/actions/runners$2"; }
    api GET '?per_page=100' | jq -r --arg p "$NAME_PREFIX-" '.runners[] | select(.status == "offline" and (.name | startswith($p))) | .id' |
      while read -r id; do api DELETE "/$id" && echo "removed offline runner $id"; done || true ;;
  *) sed -n '2,10p' "$0" >&2; exit 2 ;;
esac
