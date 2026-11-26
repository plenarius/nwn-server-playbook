#!/usr/bin/env bash
# Puts the live game database back exactly as it was in one backup (chapter 12), ledger and all.
#
#   sudo ./restore-db.sh backups/<date-and-time>
#
# Run it from the game folder. Everything written to the database since that backup is lost, so it asks first.
# What it does: stops the game, empties the game's database, loads the backup into it, starts the game.
# The database itself keeps running throughout, and the characters' files are not touched.
set -euo pipefail
cd "$(dirname "$0")"

backup=${1:-}
[ -n "$backup" ] && [ -f "$backup/db.sql.gz" ] || { echo "usage: sudo ./restore-db.sh backups/<date-and-time>" >&2; exit 2; }
zcat "$backup/db.sql.gz" | tail -n 1 | grep -q 'Dump completed' || { echo "$backup/db.sql.gz is not a complete dump; nothing was changed" >&2; exit 1; }

container() { # found by name, as in backup.sh, so it works under plain Compose and under Coolify
  local ids; ids=$(docker ps -q --filter "label=com.docker.compose.service=$1")
  [ "$(printf '%s' "$ids" | grep -c .)" = 1 ] || { echo "expected one running '$1' container, found $(printf '%s' "$ids" | grep -c .)" >&2; exit 1; }
  echo "$ids"
}
db=$(container mariadb)
game=$(container nwserver)
sql() { docker exec -i "$db" sh -c 'MYSQL_PWD="$MARIADB_PASSWORD" exec mariadb -u"$MARIADB_USER" '"$*"; }

echo "This replaces the live game database with $backup. Everything stored since then is lost."
if [ "${RESTORE_YES:-}" != yes ]; then
  read -r -p "Type restore to go on: " answer
  [ "$answer" = restore ] || { echo "nothing was changed"; exit 1; }
fi

docker stop "$game" > /dev/null && echo "game stopped"
# Emptied by dropping and making the database again, as the game's own account, so tables added since the
# backup go too. The account keeps its rights, which belong to the database's name.
echo 'DROP DATABASE `'"$(docker exec "$db" printenv MARIADB_DATABASE)"'`; CREATE DATABASE `'"$(docker exec "$db" printenv MARIADB_DATABASE)"'`;' | sql
zcat "$backup/db.sql.gz" | sql '"$MARIADB_DATABASE"'
echo "database restored from $backup"
docker start "$game" > /dev/null && echo "game started"
