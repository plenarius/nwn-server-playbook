#!/usr/bin/env bash
# Builds your custom content on the control host, publishes it for players' games, tidies old versions away,
# and sends the files to the game host's ~/incoming for release.sh (chapter 16).
#
#   publish.sh MODULE.mod       the module the content is for (its hak list decides what goes in, and the order)
#
# Settings, from the environment:
#   CONTENT_DIR   your content repository, cloned on this machine     (default ~/myhaks)
#   NWSYNC_DIR    the folder the downloads service serves             (default ~/nwsync)
#   GAME          the game host's private address                     (default 10.77.0.2)
#   GAME_USER     the deploy user there                               (default nwn)
#   KEEP          how many of the newest versions always stay         (default 3)
#
# Old versions are removed only when they are not the newest KEEP, not what "latest" names, not what the live game
# is offering right now, and older than 7 days. Only one publish runs at a time.
set -euo pipefail

module=${1:?give the module file, e.g. ~/mymodule.mod}
CONTENT_DIR=${CONTENT_DIR:-$HOME/myhaks}
NWSYNC_DIR=${NWSYNC_DIR:-$HOME/nwsync}
GAME=${GAME:-10.77.0.2}
GAME_USER=${GAME_USER:-nwn}
KEEP=${KEEP:-3}
export PATH=$HOME/nwn-tools:$PATH

exec 9> "$NWSYNC_DIR/.publish.lock"
flock -n 9 || { echo "another publish is running" >&2; exit 1; }

# 1. Build from the repository's newest commit.
git -C "$CONTENT_DIR" pull -q --ff-only
"$CONTENT_DIR/build.sh" 2>&1 | grep -v 'erf header'

# 2. Write the new version. The running game keeps offering the old one until its next start.
# Its log is long, so it is shown only if writing fails.
log=$(mktemp)
nwn_nwsync_write --description="$(basename "$module" .mod)" \
  --path "$CONTENT_DIR/build/hak" --path "$CONTENT_DIR/build/tlk" "$NWSYNC_DIR" "$module" > "$log" 2>&1 ||
  { cat "$log" >&2; rm -f "$log"; exit 1; }
rm -f "$log"
new=$(cat "$NWSYNC_DIR/latest")
echo "published $new"

# 3. Send the files to the game host for release.sh.
ssh "$GAME_USER@$GAME" 'mkdir -p ~/incoming'
scp -q "$CONTENT_DIR"/build/hak/*.hak "$CONTENT_DIR"/build/tlk/*.tlk "$module" "$GAME_USER@$GAME:incoming/"
echo "sent to $GAME:incoming; release them there with: sudo ./release.sh"

# 4. Tidy: decide what must stay, then let the NWSync tool remove whatever no kept version uses.
live=$(ssh "$GAME_USER@$GAME" 'docker logs "$(docker ps -q --filter label=com.docker.compose.service=nwserver)" 2>&1 |
  grep -a "now advertising" | tail -n 1 | grep -o "[0-9a-f]\{40\}"' || true)
[ -n "$live" ] || { echo "could not tell which version the game is offering; nothing removed"; exit 0; }
keep=$(ls -1t "$NWSYNC_DIR"/manifests/ | grep -E '^[0-9a-f]{40}$' | head -n "$KEEP")
for path in "$NWSYNC_DIR"/manifests/*; do
  name=$(basename "$path"); hash=${name%.json}
  [[ $hash =~ ^[0-9a-f]{40}$ ]] || continue
  if [ "$hash" = "$new" ] || [ "$hash" = "$live" ] || grep -qx "$hash" <<< "$keep" ||
     [ -n "$(find "$path" -mtime -7)" ]; then continue; fi
  rm -f "$path"
  [ "$name" = "$hash" ] && echo "removed old version $hash"
done
nwn_nwsync_prune --min-age 604800 "$NWSYNC_DIR" > /dev/null 2>&1
echo "kept: the newest $KEEP, the game's current $live, and anything from the last 7 days"
