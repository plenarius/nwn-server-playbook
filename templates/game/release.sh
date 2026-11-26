#!/usr/bin/env bash
# Puts a new module, new haks or a new talk table on the game server, carefully.
#
#   sudo ./release.sh           install what is in ~/incoming  (any of *.mod, *.hak, *.tlk, and a migrations/ folder)
#   sudo ./release.sh --undo    put back what the last release replaced
#
# Run it from the game folder. What it does, in order:
#   1. if there is a migrations/ folder, checks it against the database's ledger (chapter 5), and stops if a file
#      that already ran was changed;
#   2. makes a backup with ./backup.sh, and stops if that fails;
#   3. if there are migrations waiting, rehearses them on a copy of that backup, and stops if that fails;
#   4. keeps a copy of every file it is about to replace, in releases/<date-and-time>/;
#   5. stops the game, applies the migrations, replaces the files, starts the game. If a migration fails, the old
#      files stay and the old game starts again;
#   6. waits until the game is healthy, and tells you plainly if it is not.
# Until step 5 the game keeps running, so a refusal before then costs your players nothing.
# The game is away for a few seconds. Settings are not touched: if they changed too, apply them afterwards
# ("docker compose up -d" in tier 1, a redeploy in Coolify in tier 2).
set -euo pipefail
cd "$(dirname "$0")"

owner=$(stat -c %U .)
incoming=$(getent passwd "$owner" | cut -d: -f6)/incoming

# The game's containers, found by the name the compose file gives them. This works whether plain Docker Compose
# (tier 1) or Coolify (tier 2) started them.
container() {
  local ids; ids=$(docker ps -aq --filter "label=com.docker.compose.service=$1")
  [ "$(printf '%s' "$ids" | grep -c .)" = 1 ] || { echo "expected one '$1' container, found $(printf '%s' "$ids" | grep -c .)" >&2; exit 1; }
  echo "$ids"
}

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
    [ "$(docker inspect -f '{{.State.Health.Status}}' "$(container nwserver)" 2>/dev/null)" = healthy ] && return 0
    sleep 2
  done
  return 1
}

stop_game() { docker stop "$(container nwserver)" > /dev/null && echo "game stopped"; }
start_game() { docker start "$(container nwserver)" > /dev/null && echo "game started"; }

swap() { # folder holding the files to install; folder to keep the replaced ones in (or "" for none)
  local from=$1 keep=$2 f name d
  for f in "$from"/*; do
    name=$(basename "$f"); d=$(dest "$name") || continue
    mkdir -p "$d"
    if [ -n "$keep" ] && [ -e "$d/$name" ]; then cp -p "$d/$name" "$keep/"; fi
    cp "$f" "$d/$name.new" && mv -f "$d/$name.new" "$d/$name"
    echo "installed $d/$name"
  done
}

if [ "${1:-}" = "--undo" ]; then
  last=$(find releases -mindepth 1 -maxdepth 1 -type d ! -name '*.undone' 2>/dev/null | sort | tail -n 1)
  [ -n "$last" ] && [ -n "$(ls -A "$last")" ] || { echo "there is no earlier release to put back" >&2; exit 1; }
  echo "putting back the files kept in $last"
  stop_game; swap "$last" ""; start_game
  mv "$last" "$last.undone"
  if [ -s "$last.undone/migrations-applied" ]; then
    echo "note: that release also changed the database, and the files going back don't undo that:" >&2
    sed 's/^/  /' "$last.undone/migrations-applied" >&2
    echo "the backup made just before it is $(cat "$last.undone/backup-before"); chapter 5 shows how to restore it" >&2
  fi
else
  shopt -s nullglob
  files=("$incoming"/*.mod "$incoming"/*.hak "$incoming"/*.tlk)
  mig=$incoming/migrations
  [ -d "$mig" ] || mig=""
  [ ${#files[@]} -gt 0 ] || [ -n "$mig" ] || { echo "nothing to release: put .mod, .hak or .tlk files, or a migrations folder, in $incoming" >&2; exit 1; }
  waiting=""
  if [ -n "$mig" ]; then
    st=$(MIGRATIONS=$mig ./migrate.sh status) || { echo "$st"; echo "release stopped before anything changed: see the problem above" >&2; exit 1; }
    echo "$st"
    waiting=$(sed -n 's/^  waiting: //p' <<< "$st")
  fi
  backup=$(./backup.sh | tee /dev/stderr | sed -n 's/^backup made: \([^ ]*\).*/\1/p')
  if [ -n "$waiting" ]; then
    MIGRATIONS=$mig BACKUP=$backup ./migrate.sh rehearse || { echo "release stopped before anything changed: the migrations failed on a copy" >&2; exit 1; }
  fi
  keep=releases/$(date -u +%Y%m%d-%H%M%S)
  mkdir -p "$keep"
  echo "$backup" > "$keep/backup-before"
  stop_game
  if [ -n "$waiting" ]; then
    if ! MIGRATIONS=$mig ./migrate.sh apply; then
      echo "a migration failed on the live database; the old files stay, and the old game starts again" >&2
      start_game; rm -rf "$keep"
      echo "the backup made just before is $backup; chapter 5 shows how to look at what happened and how to restore it" >&2
      exit 1
    fi
    printf '%s\n' "$waiting" > "$keep/migrations-applied"
  fi
  swap "$incoming" "$keep"
  start_game
  mkdir -p "$incoming/done"
  if [ ${#files[@]} -gt 0 ]; then mv "${files[@]}" "$incoming/done/"; fi
  if [ -n "$mig" ]; then
    # The game folder keeps the newest copy of the migrations, so ./migrate.sh status works there between releases.
    rm -rf migrations && cp -r "$mig" migrations
    rm -rf "$incoming/done/migrations" && mv "$mig" "$incoming/done/migrations"
    chown -R "$owner": migrations
  fi
  chown -R "$owner": releases "$incoming/done"
fi

if wait_healthy; then
  echo "the game is healthy again"
else
  echo "the game did not become healthy within three minutes" >&2
  echo "look at:  docker logs --tail 50 $(container nwserver)      and to go back:  sudo ./release.sh --undo" >&2
  exit 1
fi
