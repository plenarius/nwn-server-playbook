#!/usr/bin/env bash
# Puts a new module, new haks or a new talk table on the game server, carefully.
#
#   sudo ./release.sh           install what is in ~/incoming  (any of *.mod, *.hak, *.tlk)
#   sudo ./release.sh --undo    put back what the last release replaced
#
# Run it from the game folder. What it does, in order:
#   1. makes a backup with ./backup.sh, and stops if that fails;
#   2. keeps a copy of every file it is about to replace, in releases/<date-and-time>/;
#   3. stops the game, replaces the files, starts the game;
#   4. waits until the game is healthy, and tells you plainly if it is not.
# The game is away for a few seconds. Settings are not touched: if .env changed too, run
# "docker compose up -d" afterwards.
set -euo pipefail
cd "$(dirname "$0")"

owner=$(stat -c %U .)
incoming=$(getent passwd "$owner" | cut -d: -f6)/incoming

dest() { # where a file of this kind lives
  case $1 in
    *.mod) echo home/modules ;;
    *.hak) echo home/hak ;;
    *.tlk) echo home/tlk ;;
    *) return 1 ;;
  esac
}

wait_healthy() {
  for _ in $(seq 90); do
    [ "$(docker inspect -f '{{.State.Health.Status}}' "$(docker compose ps -q nwserver)" 2>/dev/null)" = healthy ] && return 0
    sleep 2
  done
  return 1
}

swap() { # folder holding the files to install; folder to keep the replaced ones in (or "" for none)
  local from=$1 keep=$2 f name d
  docker compose stop nwserver
  for f in "$from"/*; do
    name=$(basename "$f"); d=$(dest "$name") || continue
    mkdir -p "$d"
    if [ -n "$keep" ] && [ -e "$d/$name" ]; then cp -p "$d/$name" "$keep/"; fi
    cp "$f" "$d/$name.new" && mv -f "$d/$name.new" "$d/$name"
    echo "installed $d/$name"
  done
  docker compose start nwserver
}

if [ "${1:-}" = "--undo" ]; then
  last=$(find releases -mindepth 1 -maxdepth 1 -type d ! -name '*.undone' 2>/dev/null | sort | tail -n 1)
  [ -n "$last" ] && [ -n "$(ls -A "$last")" ] || { echo "there is no earlier release to put back" >&2; exit 1; }
  echo "putting back the files kept in $last"
  swap "$last" ""
  mv "$last" "$last.undone"
else
  shopt -s nullglob
  files=("$incoming"/*.mod "$incoming"/*.hak "$incoming"/*.tlk)
  [ ${#files[@]} -gt 0 ] || { echo "nothing to release: put .mod, .hak or .tlk files in $incoming" >&2; exit 1; }
  ./backup.sh
  keep=releases/$(date -u +%Y%m%d-%H%M%S)
  mkdir -p "$keep"
  swap "$incoming" "$keep"
  mkdir -p "$incoming/done" && mv "${files[@]}" "$incoming/done/"
  chown -R "$owner": releases "$incoming/done"
fi

if wait_healthy; then
  echo "the game is healthy again"
else
  echo "the game did not become healthy within three minutes" >&2
  echo "look at:  docker compose logs --tail 50 nwserver      and to go back:  sudo ./release.sh --undo" >&2
  exit 1
fi
