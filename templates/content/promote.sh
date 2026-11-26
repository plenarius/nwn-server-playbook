#!/usr/bin/env bash
# Releases what publish.sh staged: points "latest" at the staged version, then runs release.sh on the game host,
# which swaps in the haks, the talk table and the module and restarts the game. Then it tidies old versions away.
#
#   promote.sh            release the staged version
#   promote.sh --back     go back to the version before: "latest" back, and release.sh --undo on the game host
#
# Settings: content.env beside this script (see content.env.example).
set -euo pipefail
. "$(dirname "$0")/lib.sh"

release() { # release.sh's arguments
  ssh "$GAME_USER@$GAME" "cd $GAME_DIR && sudo ./release.sh $*"
}

check_live() { # the version the game should now hand out
  local live; live=$(live_version)
  if [ "$live" = "$1" ]; then echo "the game hands out $1"
  else echo "the game says it hands out '${live:-nothing}', not $1: look at its log" >&2; return 1; fi
}

if [ "${1:-}" = "--back" ]; then
  [ -s "$PREVIOUS_FILE" ] || { echo "there is no earlier version to go back to" >&2; exit 1; }
  back=$(cat "$PREVIOUS_FILE")
  [ -f "$NWSYNC_DIR/manifests/$back" ] || { echo "version $back is no longer in $NWSYNC_DIR" >&2; exit 1; }
  set_latest "$back"
  echo "latest is $back again"
  release --undo
  rm -f "$PREVIOUS_FILE"
  check_live "$back"
  exit 0
fi

[ -s "$STAGED_FILE" ] || { echo "nothing is staged: run publish.sh first" >&2; exit 1; }
new=$(cat "$STAGED_FILE")
[ -f "$NWSYNC_DIR/manifests/$new" ] || { echo "the staged version $new is missing from $NWSYNC_DIR" >&2; exit 1; }
old=$(cat "$NWSYNC_DIR/latest" 2>/dev/null || true)
was_previous=$(cat "$PREVIOUS_FILE" 2>/dev/null || true)
last_release() { ssh "$GAME_USER@$GAME" "ls -1 $GAME_DIR/releases 2>/dev/null | tail -n 1"; }
before=$(last_release)

# "latest" first, so the game reads the new version when release.sh restarts it.
[ -z "$old" ] || [ "$old" = "$new" ] || echo "$old" > "$PREVIOUS_FILE"
set_latest "$new"
echo "latest is $new (was $old)"
if ! release; then
  after=$(last_release) || after="(could not ask)"
  if [ "$after" = "$before" ] && [ -n "$old" ]; then
    # release.sh refused before it changed a file (a failed backup, a migration that failed its rehearsal or on
    # the live database): the old haks are still in place, so "latest" goes back to the old version at once.
    set_latest "$old"
    if [ -n "$was_previous" ]; then echo "$was_previous" > "$PREVIOUS_FILE"; else rm -f "$PREVIOUS_FILE"; fi
    echo "the release stopped before it changed any file; latest is $old again, and $new is still staged" >&2
  else
    echo "the release changed files and the game is not healthy. To go back to $old and the old files: $0 --back" >&2
  fi
  exit 1
fi
rm -f "$STAGED_FILE"
check_live "$new"
"$here/prune.sh"
