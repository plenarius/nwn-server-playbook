#!/usr/bin/env bash
# Tidies old versions out of the download folder. promote.sh runs it after every release; run it by hand only if
# you know why.
#
# A version is removed only when all of these hold: it isn't among the newest KEEP, it isn't what "latest" names,
# it isn't staged, it isn't the one promote.sh --back would go back to, it isn't what the live game says it
# hands out, and it is older than MIN_AGE_DAYS. If the game can't be asked, nothing is removed. Content files no
# remaining version uses go too, once they are MIN_AGE_DAYS old.
#
# Settings: content.env beside this script (see content.env.example).
set -euo pipefail
. "$(dirname "$0")/lib.sh"

live=$(live_version)
[ -n "$live" ] || { echo "could not tell which version the game hands out; nothing removed"; exit 0; }
val() { cat "$1" 2>/dev/null || true; }
newest=$(ls -1t "$NWSYNC_DIR/manifests/" | grep -E '^[0-9a-f]{40}$' | head -n "$KEEP" || true)
protect="$(val "$NWSYNC_DIR/latest") $live $(val "$STAGED_FILE") $(val "$PREVIOUS_FILE") $(tr '\n' ' ' <<< "$newest")"

for path in "$NWSYNC_DIR"/manifests/*; do
  name=$(basename "$path"); hash=${name:0:40}
  [[ $hash =~ ^[0-9a-f]{40}$ ]] || continue
  grep -qw "$hash" <<< "$protect" && continue
  [ -n "$(find "$path" -mtime "-$MIN_AGE_DAYS")" ] && continue
  rm -f "$path"
  [ "$name" = "$hash" ] && echo "removed old version $hash"
done
in_image nwn_nwsync_prune --min-age $((MIN_AGE_DAYS * 86400)) /nwsync > /dev/null 2>&1
echo "kept: latest, the staged one, the one to go back to, the game's $live, the newest $KEEP, the last $MIN_AGE_DAYS days"
