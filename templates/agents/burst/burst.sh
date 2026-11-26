#!/usr/bin/env bash
# burst.sh: a big server for a few hours, for batch work, that is gone at a fixed time whatever happens.
# Run on the hub. Built on chapter 1's hcloud-servers (labels, expiry, budget, reaper). Chapter 15, tier 3.
#
#   burst.sh start NAME TYPE HOURS [LOCATION] [IMAGE]   make it, and set its own delete at the expiry
#   burst.sh secrets NAME FILE [AGENT_USER]             the agent's tokens into its memory (/run/agent)
#   burst.sh status NAME                                address and minutes left
#   burst.sh collect NAME                               copy /srv/burst-out from it to OUT_DIR
#   burst.sh stop NAME                                  collect, then delete it
#
# What start adds to hcloud-servers create: it waits for SSH; puts the provider token in /run/burst (memory,
# root, 600) over SSH's standard input, never in user_data, which the provider keeps; starts a timer on the
# server that deletes it through the API at its expiry (a time on the clock, not "in N hours", which can move);
# writes the deadline to /etc/burst-expires for agents; and makes /srv/burst-out for their results. It warns
# on the server before the end (WARN_MIN) and copies the results to the hub first (COLLECT_MIN). Any failure
# during start deletes the server. Settings: ~/.config/agent-burst/burst.env (BURST_SETTINGS= for another).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SETTINGS=${BURST_SETTINGS:-$HOME/.config/agent-burst/burst.env}
set -a; . "$SETTINGS"; set +a
HCLOUD_TOKEN_FILE=${HCLOUD_TOKEN_FILE/#\~/$HOME} SSH_KEY=${SSH_KEY/#\~/$HOME}
KNOWN_HOSTS=${KNOWN_HOSTS/#\~/$HOME} OUT_DIR=${OUT_DIR/#\~/$HOME}
export HCLOUD_TOKEN_FILE IPV6=${IPV6:-0}
HS=${HCLOUD_SERVERS:-hcloud-servers}
mkdir -p "$(dirname "$KNOWN_HOSTS")"
SSHR=(ssh -i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5
      -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN_HOSTS")

server() { # NAME -> "ip expires" of one of hcloud-servers' own servers, from the API
  python3 - "$1" <<'PY'
import json, os, sys, urllib.parse, urllib.request
tok = open(os.environ["HCLOUD_TOKEN_FILE"]).read().strip()
req = urllib.request.Request("https://api.hetzner.cloud/v1/servers?name=" + urllib.parse.quote(sys.argv[1]),
                             headers={"Authorization": "Bearer " + tok})
s = json.load(urllib.request.urlopen(req, timeout=30))["servers"]
if not s or s[0]["labels"].get("managed-by") != os.environ.get("MANAGED_BY", "playbook"):
    sys.exit("no burst server named " + sys.argv[1])
print(s[0]["public_net"]["ipv4"]["ip"], s[0]["labels"]["expires"])
PY
}

case ${1:-} in
start)
  name=$2 type=$3 hours=$4 loc=${5:-hel1} image=${6:-ubuntu-26.04}
  ip=$("$HS" create "$name" "$type" "$hours" "$loc" "$image")
  trap 'echo "start of $name failed; deleting it" >&2; "$HS" delete "$name" >&2 || true' EXIT
  read -r _ expires < <(server "$name")
  ssh-keygen -R "$ip" -f "$KNOWN_HOSTS" >/dev/null 2>&1 || true
  up=
  for _ in $(seq 60); do "${SSHR[@]}" "root@$ip" true 2>/dev/null && { up=1; break; }; sleep 5; done
  [ -n "$up" ] || { echo "$name never answered SSH" >&2; exit 1; }
  "${SSHR[@]}" "root@$ip" 'install -d -m 700 /run/burst && umask 077 && cat > /run/burst/token' < "$HCLOUD_TOKEN_FILE"
  "${SSHR[@]}" "root@$ip" 'cat > /usr/local/sbin/self-destruct && chmod 700 /usr/local/sbin/self-destruct' < "$HERE/self-destruct"
  "${SSHR[@]}" "root@$ip" bash -s -- "$expires" "$WARN_MIN" <<'REMOTE'
set -euo pipefail
expires=$1
systemd-run -q --unit=self-destruct --on-calendar="@$expires" --timer-property=AccuracySec=10s /usr/local/sbin/self-destruct
date -u -d "@$expires" '+%Y-%m-%d %H:%M UTC' > /etc/burst-expires
install -d -m 1777 /srv/burst-out
for m in ${2:-}; do
  at=$((expires - m * 60)); [ "$at" -gt "$(date +%s)" ] || continue
  systemd-run -q --unit="burst-warn-$m" --on-calendar="@$at" /bin/sh -c \
    "echo 'This server is deleted in $m minutes ($(cat /etc/burst-expires)). Push your work and put results in /srv/burst-out.' | tee /run/burst/warning | wall"
done
systemctl is-active -q self-destruct.timer && echo "self-destruct at $(cat /etc/burst-expires)"
REMOTE
  for m in $COLLECT_MIN; do
    at=$((expires - m * 60)); [ "$at" -gt "$(date +%s)" ] || continue
    systemd-run --user -q --unit="burst-collect-$name-$m" --on-calendar="@$at" "$HERE/burst.sh" collect "$name"
  done
  trap - EXIT
  echo "$ip"
  ;;
secrets)
  read -r ip _ < <(server "$2"); file=$3 user=${4:-agent}
  [ "$(stat -c %a "$file")" = 600 ] || { echo "$file must be mode 600" >&2; exit 1; }
  "${SSHR[@]}" "root@$ip" "id $user >/dev/null && install -d -m 700 -o $user -g $user /run/agent &&
    install -m 600 -o $user -g $user /dev/stdin /run/agent/secrets.env && sed -n 's/=.*//p' /run/agent/secrets.env | tr '\n' ' '" < "$file"
  echo "<- in /run/agent/secrets.env on $2"
  ;;
status)
  read -r ip expires < <(server "$2")
  echo "$2 $ip $(( (expires - $(date +%s)) / 60 )) min left"
  ;;
collect)
  read -r ip _ < <(server "$2")
  dest=$OUT_DIR/$2/$(date -u +%Y%m%d-%H%M)
  mkdir -p "$dest"
  rsync -a -e "${SSHR[*]}" "root@$ip:/srv/burst-out/" "$dest/"
  echo "collected $(find "$dest" -type f | wc -l) file(s) into $dest"
  ;;
stop)
  "$0" collect "$2" || echo "collect failed; deleting anyway" >&2
  "$HS" delete "$2"
  for u in $(systemctl --user list-units --plain --no-legend "burst-collect-$2-*" | awk '{print $1}'); do
    systemctl --user stop "$u" 2>/dev/null || true; done
  ;;
*) sed -n '5,10p' "$0" >&2; exit 2 ;;
esac
