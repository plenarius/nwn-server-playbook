#!/usr/bin/env bash
# Builds your custom content on the control host and stages it: the new version is written beside the live one
# and checked over HTTPS the way a player's game would fetch it, and the files wait on the game host. Players
# see none of it until promote.sh.
#
#   publish.sh MODULE.mod       the module the content is for (its hak list decides what goes in, and the order)
#
# Settings: content.env beside this script (see content.env.example).
set -euo pipefail
module=$(realpath "${1:?give the module file, e.g. ~/mymodule.mod}")
. "$(dirname "$0")/lib.sh"
extra_mounts=(-v "$module:/module.mod:ro")
rm -f "$STAGED_FILE"   # whatever was staged before is replaced by this run

# 1. Build from the repository's newest commit, in the builder image.
git -C "$CONTENT_DIR" pull -q --ff-only
in_image /src/build.sh 2>&1 | grep -v 'erf header'

# 2. Write the new version beside the others. "latest" is not touched, so a game that starts now, even by
# accident, still hands out the version that matches its haks. The tool's log is shown only if writing fails.
log=$(mktemp)
json=$(in_image nwn_nwsync_write --no-latest --description="$(basename "$module" .mod)" \
  --path /src/build/hak --path /src/build/tlk /nwsync /module.mod 2> "$log") ||
  { cat "$log" >&2; rm -f "$log"; exit 1; }
rm -f "$log"
new=$(grep -o '"sha1": *"[0-9a-f]\{40\}"' <<< "$json" | grep -o '[0-9a-f]\{40\}' || true)
[[ $new =~ ^[0-9a-f]{40}$ ]] || { echo "the NWSync tool did not name a version" >&2; exit 1; }
echo "written $new"

# 3. Check it from outside, as a player's game would: fetch the version over HTTPS into an empty folder and
# compare every file with its checksum.
in_image nwsync-check "$NWSYNC_URL" "$new" ||
  { echo "the check of $NWSYNC_URL failed: players could not download $new" >&2; exit 1; }
echo "checked: $NWSYNC_URL hands out $new completely"

# 4. Send the files to the game host's ~/incoming for the release, replacing anything staged there before,
# and check they arrived whole.
files=("$CONTENT_DIR"/build/hak/*.hak "$CONTENT_DIR"/build/tlk/*.tlk "$module")
ssh "$GAME_USER@$GAME" 'mkdir -p ~/incoming && rm -f ~/incoming/*.hak ~/incoming/*.tlk ~/incoming/*.mod'
scp -q "${files[@]}" "$GAME_USER@$GAME:incoming/"
want=$(cd "$(dirname "$module")" && sha256sum "$(basename "$module")"; cd "$CONTENT_DIR/build" && sha256sum hak/*.hak tlk/*.tlk)
got=$(ssh "$GAME_USER@$GAME" 'cd ~/incoming && sha256sum *.mod *.hak *.tlk')
[ "$(awk '{print $1}' <<< "$want" | sort)" = "$(awk '{print $1}' <<< "$got" | sort)" ] ||
  { echo "the files on $GAME differ from the build; send them again" >&2; exit 1; }
echo "sent ${#files[@]} files to $GAME:incoming, checked"

# Only a version that passed every check is staged, ready for promote.sh.
echo "$new" > "$STAGED_FILE"
echo "staged $new"

echo "players still get $(cat "$NWSYNC_DIR/latest" 2>/dev/null || echo nothing yet). To release: $(dirname "$0")/promote.sh"
