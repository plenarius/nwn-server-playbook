#!/usr/bin/env bash
# Keeps the operations API's own copy of the game's files in step with the game host (chapter 9, tier 3): the
# base game's data from the image the game runs, and the live module, haks and talk table. The API reads them for
# its game data routes (talk table, 2DAs, items, character sheets). Runs on the control host as the deploy user,
# by hand or from gamedata-sync.timer; it changes nothing on the game host.
#
#   gamedata-sync.sh            copy what changed (a few seconds when nothing did)
#
# Settings, all optional, in the environment or in ~/ops-api/gamedata.env:
#   GAME=10.77.0.2          the game host's private address
#   GAME_USER=nwn           the deploy user there
#   GAME_DIR=game           the game's folder there (its .env names the live module)
#   DEST=~/ops-api/gamedata the folder the API's container mounts read-only as /data/game
set -euo pipefail
[ -f ~/ops-api/gamedata.env ] && . ~/ops-api/gamedata.env
GAME=${GAME:-10.77.0.2}
GAME_USER=${GAME_USER:-nwn}
GAME_DIR=${GAME_DIR:-game}
DEST=${DEST:-$HOME/ops-api/gamedata}
on_game() { ssh -o BatchMode=yes "$GAME_USER@$GAME" "$@"; }

exec 9> "$DEST.lock"
flock -n 9 || { echo "another gamedata-sync is running" >&2; exit 1; }
mkdir -p "$DEST/nwn" "$DEST/hak" "$DEST/tlk"

# 1. The base game: the image's /nwn/data (its key and bif files and dialog.tlk, about 220 MB), copied again only
# when the game runs a different image. It goes into a new folder and is swapped in whole, so the API never reads
# half of one version and half of another.
ctr=$(on_game 'docker ps -q --filter label=com.docker.compose.service=nwserver | head -n 1')
image=$([ -n "$ctr" ] && on_game "docker inspect -f '{{.Image}}' $ctr" || true)
if [ -z "$ctr" ]; then
  echo "the game isn't running: base game data left as it was"
elif [ "$(cat "$DEST/nwn/.image" 2>/dev/null)" != "$image" ]; then
  rm -rf "$DEST/nwn.new" && mkdir "$DEST/nwn.new"
  on_game "docker cp $ctr:/nwn/data/data - && docker cp $ctr:/nwn/data/lang -" | tar -x -i -C "$DEST/nwn.new"
  test -s "$DEST/nwn.new/data/nwn_base.key" && test -s "$DEST/nwn.new/lang/en/data/dialog.tlk" ||
    { echo "the image's game data is not where it should be; kept the old copy" >&2; exit 1; }
  echo "$image" > "$DEST/nwn.new/.image"
  rm -rf "$DEST/nwn.old" && mv "$DEST/nwn" "$DEST/nwn.old" && mv "$DEST/nwn.new" "$DEST/nwn" && rm -rf "$DEST/nwn.old"
  echo "base game data copied from the image $(cut -c8-19 <<< "$image")"
fi

# 2. The module the game runs, under one fixed name the API's settings point at, and the live haks and talk
# table (never the staged ones: those aren't live until a deploy). --delay-updates puts every changed file in
# place at the end, so the API sees one version or the other.
module=$(on_game "grep -m1 '^NWN_MODULE=' $GAME_DIR/.env | cut -d= -f2-")
[ -n "$module" ] || { echo "no NWN_MODULE in $GAME_DIR/.env on $GAME" >&2; exit 1; }
rs() { rsync -rt --delete --delay-updates --itemize-changes "$@" | grep -c '^>f' || true; }
n=$(rs --copy-links "$GAME_USER@$GAME:$GAME_DIR/home/modules/$module.mod" "$DEST/module.mod")
h=$(rs --include='*.hak' --exclude='*' "$GAME_USER@$GAME:$GAME_DIR/home/hak/" "$DEST/hak/")
t=$(rs --include='*.tlk' --exclude='*' "$GAME_USER@$GAME:$GAME_DIR/home/tlk/" "$DEST/tlk/")
echo "module $module ($n changed), haks: $h changed, talk tables: $t changed"
