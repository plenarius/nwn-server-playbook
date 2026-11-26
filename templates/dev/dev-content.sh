#!/usr/bin/env bash
# The dev server's own custom content (chapter 14, tier 3): builders' haks on top of the live ones, served from a
# second NWSync address that has only the new files and falls back to the live download folder for the rest.
# dev.sh runs this before each restart; you rarely run it by hand:
#
#   ~/dev/dev-content.sh            build the dev content for the module loaded on the dev server now
#
# It reads chapter 7's settings (~/content/content.env, through lib.sh): CONTENT_DIR's build/hak and build/tlk are
# the live haks, NWSYNC_DIR the live download folder. It never writes to either. The dev server's address is its
# own NWN_NWSYNCURL setting in Coolify.
#
# What it makes:
#   ~/dev/home/hak, ~/dev/home/tlk   the live build's haks and talk tables, with ~/dev/content/hak/*.hak over them
#   ~/dev/nwsync                     only the files the live folder lacks, a manifest, and "latest"
set -euo pipefail
dev=$(cd "$(dirname "$0")" && pwd)
. "${CONTENT_SCRIPTS:-$HOME/content}/lib.sh"
live=$NWSYNC_DIR

game=$(docker ps -aq --filter label=com.docker.compose.service=dev-nwserver)
[ "$(printf '%s' "$game" | grep -c .)" = 1 ] || { echo "expected one dev-nwserver container" >&2; exit 1; }
setting() { docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$game" | sed -n "s/^$1=//p"; }
module=$(setting NWN_MODULE)
url=$(setting NWN_NWSYNCURL); url=${url%/}
[[ $url =~ ^https:// ]] || { echo "the dev game has no NWN_NWSYNCURL: dev content is off" >&2; exit 1; }
[ "$url" != "$NWSYNC_URL" ] || { echo "the dev game's NWN_NWSYNCURL is the live address; give it its own" >&2; exit 1; }
mod=$dev/home/modules/$module.mod
[ -f "$mod" ] || { echo "no module loaded on the dev server yet" >&2; exit 1; }
[ -s "$live/latest" ] || { echo "the live download folder $live has no version yet (chapter 7)" >&2; exit 1; }

# 1. The dev game's haks: the live build's, then the builders' over them. Each file goes into place by renaming, so
# a running dev game never reads a half-copied hak.
mkdir -p "$dev/content/hak" "$dev/home/hak" "$dev/home/tlk" "$dev/nwsync/data" "$dev/nwsync/manifests"
rsync -a --delete "$CONTENT_DIR/build/tlk/" "$dev/home/tlk/"
rsync -a --delete --exclude-from=<(cd "$dev/content/hak" && ls) "$CONTENT_DIR/build/hak/" "$dev/home/hak/"
rsync -a "$dev/content/hak/" "$dev/home/hak/"
mine=$(cd "$dev/content/hak" && ls -- *.hak 2>/dev/null | sed 's/\.hak$//' | paste -sd, - || true)

# 2. A version for the dev game, written where the live files are already present as hard links (nothing is
# copied, and the tool skips every file it finds). It writes new files only, so the live ones are never changed.
tmp=$(mktemp -d "$dev/.nwsync.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
cp -al "$live/data" "$tmp/data"
while IFS= read -r -d '' f; do
  [ -e "$tmp/data/$f" ] || { mkdir -p "$tmp/data/$(dirname "$f")" && ln "$dev/nwsync/data/$f" "$tmp/data/$f"; }
done < <(cd "$dev/nwsync/data" && find . -type f -print0)
mkdir "$tmp/manifests"
NWSYNC_DIR=$tmp
extra_mounts=(-v "$mod:/module.mod:ro" -v "$dev/home/hak:/hak:ro" -v "$dev/home/tlk:/tlk:ro")
log=$(mktemp -p "$tmp")
json=$(in_image nwn_nwsync_write --no-latest --description="dev: $module${mine:+ with $mine}" --path /hak --path /tlk /nwsync /module.mod 2> "$log") ||
  { cat "$log" >&2; exit 1; }
new=$(grep -o '"sha1": *"[0-9a-f]\{40\}"' <<< "$json" | grep -o '[0-9a-f]\{40\}' || true)
[[ $new =~ ^[0-9a-f]{40}$ ]] || { echo "the NWSync tool did not name a version" >&2; exit 1; }

# 3. Keep only what is new: a file with one link was written just now; the others are the live folder's, or the dev
# folder's from before. Then the manifest.
added=0
while IFS= read -r -d '' f; do
  mkdir -p "$dev/nwsync/$(dirname "$f")" && mv "$tmp/$f" "$dev/nwsync/$f"; added=$((added + 1))
done < <(cd "$tmp" && find data -type f -links 1 -print0)
cp "$tmp"/manifests/"$new"* "$dev/nwsync/manifests/"
chmod -R a+rX "$dev/nwsync"

# 4. Check it from outside, as the dev game's players will fetch it: through the dev address, which falls back to
# the live folder. Only then does "latest" move.
NWSYNC_DIR=$dev/nwsync extra_mounts=()
in_image nwsync-check "$url" "$new" > /dev/null || { echo "the check of $url failed: the dev game's players could not download $new" >&2; exit 1; }
set_latest "$new" "$dev/nwsync"
echo "dev content $new: ${mine:-no dev haks}, $added new files, the rest from live $(cat "$live/latest" | cut -c1-12)"
