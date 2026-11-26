# Shared by publish.sh, promote.sh and prune.sh (chapter 7, tier 2). Not run by itself.
# Settings come from content.env beside the scripts; see content.env.example.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[ -f "$here/content.env" ] && . "$here/content.env"
NWSYNC_URL=${NWSYNC_URL:?set NWSYNC_URL in $here/content.env}
NWSYNC_URL=${NWSYNC_URL%/}
CONTENT_DIR=${CONTENT_DIR:-$HOME/myhaks}
NWSYNC_DIR=${NWSYNC_DIR:-$HOME/nwsync}
GAME=${GAME:-10.77.0.2}
GAME_USER=${GAME_USER:-nwn}
GAME_DIR=${GAME_DIR:-game}
STAGING_DIR=${STAGING_DIR:-staging}
IMAGE=${IMAGE:-nwsync-builder:2.3.2}
BUILD_CPUS=${BUILD_CPUS:-1}
BUILD_MEMORY=${BUILD_MEMORY:-1g}
MODELS=${MODELS:-ascii}
MODEL_CACHE=${MODEL_CACHE:-$HOME/model-cache}
GAME_DATA=${GAME_DATA:-$HOME/nwn-data}
BUILDERS=${BUILDERS:-no}
KEEP=${KEEP:-3}
MIN_AGE_DAYS=${MIN_AGE_DAYS:-7}
# What is staged and what came before live with the scripts, not in the folder players download from.
STAGED_FILE=$here/staged
PREVIOUS_FILE=$here/previous

# One of these scripts at a time. promote.sh runs prune.sh while it holds the lock, and says so.
if [ -z "${CONTENT_LOCK_HELD:-}" ]; then
  exec 9> "$here/.lock"
  flock -n 9 || { echo "another publish, promote or tidy-up is running" >&2; exit 1; }
  export CONTENT_LOCK_HELD=1
fi

# Runs a command in the builder image, as this user, with the content repository at /src and the download
# folder at /nwsync. Builds the image first if it is missing. With MODELS=compile (tier 3), the model cache is at
# /cache and the game's data, read-only, at /nwn.
in_image() {
  docker image inspect "$IMAGE" > /dev/null 2>&1 ||
    { echo "building the builder image $IMAGE"; docker build -q -t "$IMAGE" "$here/builder" > /dev/null; }
  local models=()
  if [ "$MODELS" = compile ]; then
    [ -f "$GAME_DATA/data/nwn_base.key" ] || { echo "MODELS=compile: no game data in $GAME_DATA (see chapter 7, tier 3)" >&2; return 1; }
    mkdir -p "$MODEL_CACHE"
    models=(-e MODELS=compile -e MODEL_CACHE=/cache -e NWN_ROOT=/nwn -v "$MODEL_CACHE:/cache" -v "$GAME_DATA:/nwn:ro")
  fi
  docker run --rm -i --user "$(id -u):$(id -g)" --cpus "$BUILD_CPUS" --memory "$BUILD_MEMORY" \
    -v "$CONTENT_DIR:/src" -v "$NWSYNC_DIR:/nwsync" "${models[@]}" "${extra_mounts[@]}" "$IMAGE" "$@"
}
extra_mounts=()

# The version the running game hands out, from its own log; empty if it can't be told.
live_version() {
  ssh "$GAME_USER@$GAME" 'docker logs "$(docker ps -q --filter label=com.docker.compose.service=nwserver)" 2>&1 |
    grep -a "now advertising" | tail -n 1 | grep -o "[0-9a-f]\{40\}"' 2>/dev/null || true
}

# Moves "latest" to a version in one step, so nobody ever reads a half-written file. A second argument names
# another folder's "latest" (the staging one).
set_latest() {
  local dir=${2:-$NWSYNC_DIR}
  printf '%s' "$1" > "$dir/latest.new" && mv -f "$dir/latest.new" "$dir/latest"
}
