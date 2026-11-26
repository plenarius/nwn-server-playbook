#!/usr/bin/env bash
# Changes the game's database tables, one numbered file at a time, and remembers which files have run.
#
#   ./migrate.sh status      what has run, and what is waiting
#   ./migrate.sh apply       run the waiting files, lowest number first
#   ./migrate.sh rehearse    the same, on a throwaway copy of the newest backup; the live database is not touched
#
# Run it from the game folder. release.sh (chapter 16) runs all three for you when a release carries migrations.
#
# A migration is a file named like 0001-what-it-does.sql: four digits, a dash, lowercase words. Other files are
# ignored. The ledger, a table called schema_migrations, records each file that ran: its name, a checksum of its
# exact contents, and when. The script refuses to run anything if a file that already ran has been changed or
# removed: a file that ran is history, and a correction is a new, higher-numbered file.
#
# Each file runs in one session together with the line that records it, so a file is recorded only if every
# statement in it worked. If one fails, the script stops there: that file is not recorded and later files don't run.
# Row changes after the file's last table change are undone with it. Table changes (CREATE, ALTER, DROP) can't be
# undone by MariaDB, and they commit any row changes made before them, which is why each file should be safe to run
# twice (CREATE TABLE IF NOT EXISTS, ADD COLUMN IF NOT EXISTS, INSERT IGNORE).
#
# Settings, from the environment:
#   MIGRATIONS     the folder of migration files (default: migrations, beside this script)
#   DB_CONTAINER   the database container (default: the one Compose or Coolify calls mariadb)
#   BACKUP         rehearse only: the backup folder to copy (default: the newest in backups/)
set -euo pipefail
cd "$(dirname "$0")"

MIGRATIONS=${MIGRATIONS:-migrations}
NAME_RE='^[0-9]{4}-[a-z0-9][a-z0-9-]*\.sql$'

# Only one copy of this script changes the database at a time.
exec 9<"$0"
flock -n 9 || { echo "another migrate.sh is already running" >&2; exit 1; }

container() { # the same way backup.sh finds it, so it works under plain Compose and under Coolify
  local ids; ids=$(docker ps -q --filter "label=com.docker.compose.service=$1")
  [ "$(printf '%s' "$ids" | grep -c .)" = 1 ] || { echo "expected one running '$1' container, found $(printf '%s' "$ids" | grep -c .)" >&2; exit 1; }
  echo "$ids"
}

# SQL on stdin, run as the game's own account. The password stays inside the container.
sql() {
  docker exec -i "$db" sh -c 'MYSQL_PWD="$MARIADB_PASSWORD" exec mariadb -u"$MARIADB_USER" --batch --skip-column-names "$MARIADB_DATABASE"'
}

ledger() {
  sql <<'SQL'
CREATE TABLE IF NOT EXISTS schema_migrations (
  name       VARCHAR(190) NOT NULL PRIMARY KEY,
  checksum   CHAR(64)     NOT NULL,
  applied_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
);
SELECT name, checksum FROM schema_migrations ORDER BY name;
SQL
}

# Compares the folder with the ledger. Fills applied/pending, prints any problem, returns 1 if there was one.
compare() {
  local f name sum out problems=0
  declare -gA done_sum=()
  applied=(); pending=()
  # If the ledger can't be read, stop: guessing would run every file again.
  out=$(ledger) || { echo "could not read the ledger from the database; nothing was run" >&2; exit 1; }
  while IFS=$'\t' read -r name sum; do [ -n "$name" ] && done_sum[$name]=$sum; done <<< "$out"
  [ -d "$MIGRATIONS" ] || { echo "no folder $MIGRATIONS: nothing to compare" >&2; }
  for f in "$MIGRATIONS"/*; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    if ! [[ $name =~ $NAME_RE ]]; then echo "ignored (not a migration name): $name"; continue; fi
    sum=$(sha256sum "$f" | cut -d' ' -f1)
    if [ -z "${done_sum[$name]:-}" ]; then
      pending+=("$name")
    elif [ "${done_sum[$name]}" != "$sum" ]; then
      echo "PROBLEM: $name has changed since it ran (recorded ${done_sum[$name]:0:12}, now ${sum:0:12}). Put it back as it was, and make the change in a new file." >&2
      problems=1
    else
      applied+=("$name")
    fi
  done
  for name in "${!done_sum[@]}"; do
    [ -f "$MIGRATIONS/$name" ] || { echo "PROBLEM: $name ran, but its file is not in $MIGRATIONS. Put it back." >&2; problems=1; }
  done
  return $problems
}

apply() {
  local name sum
  compare || { echo "nothing was run" >&2; return 1; }
  [ ${#pending[@]} -gt 0 ] || { echo "nothing to apply (${#applied[@]} already applied)"; return 0; }
  for name in "${pending[@]}"; do
    sum=$(sha256sum "$MIGRATIONS/$name" | cut -d' ' -f1)
    echo "applying $name"
    # One session: the file, then the line that records it, with autocommit off. The client stops at the first
    # error, so a file that fails is never recorded, and row changes not yet committed are rolled back with the
    # session. A table change (CREATE, ALTER, DROP) commits by itself, together with any row changes before it.
    if ! { echo "SET autocommit = 0;"; cat "$MIGRATIONS/$name"; printf '\nINSERT INTO schema_migrations (name, checksum) VALUES (%s, %s);\nCOMMIT;\n' "'$name'" "'$sum'"; } | sql; then
      echo "FAILED: $name. It was not recorded, and nothing after it ran." >&2
      return 1
    fi
  done
  echo "applied ${#pending[@]}, ${#applied[@]} were already applied"
}

rehearse() {
  local backup=${BACKUP:-$(find backups -mindepth 1 -maxdepth 1 -type d -name '[0-9]*-[0-9]*' 2>/dev/null | sort | tail -n 1)}
  [ -n "$backup" ] && [ -f "$backup/db.sql.gz" ] || { echo "no backup to rehearse on: make one with ./backup.sh" >&2; return 1; }
  local live image user dbname
  rehearsal=migrate-rehearsal-$$
  live=$(container mariadb)
  image=$(docker inspect -f '{{.Config.Image}}' "$live")
  user=$(docker exec "$live" printenv MARIADB_USER)
  dbname=$(docker exec "$live" printenv MARIADB_DATABASE)
  echo "rehearsing on a copy of $backup, in a throwaway $image with no network"
  # The copy gets a password of its own, made here and never shown. Its storage goes when it is removed.
  docker run -d --rm --name "$rehearsal" --network none \
    -e MARIADB_RANDOM_ROOT_PASSWORD=1 -e MARIADB_DATABASE="$dbname" -e MARIADB_USER="$user" \
    -e MARIADB_PASSWORD="$(head -c 18 /dev/urandom | base64 | tr -d '/+=')" "$image" > /dev/null
  trap 'docker rm -f "$rehearsal" > /dev/null 2>&1 || true' EXIT
  db=$rehearsal
  local i
  for i in $(seq 90); do
    docker logs "$rehearsal" 2>&1 | grep -q 'init process done' && echo 'SELECT 1;' | sql > /dev/null 2>&1 && break
    [ "$i" = 90 ] && { echo "the throwaway database did not start" >&2; return 1; }
    sleep 2
  done
  zcat "$backup/db.sql.gz" | sql || { echo "the backup did not load into the copy" >&2; return 1; }
  apply || { echo "REHEARSAL FAILED: the live database was not touched" >&2; return 1; }
  # Run again: everything should now be recorded, and nothing should run twice.
  compare > /dev/null && [ ${#pending[@]} = 0 ] || { echo "REHEARSAL FAILED: a second run would not be empty" >&2; return 1; }
  echo "rehearsal passed: $(echo 'SHOW TABLES;' | sql | wc -l) tables in the copy afterwards; the copy is removed"
}

case ${1:-} in
  status)
    db=${DB_CONTAINER:-$(container mariadb)}
    ok=0; compare || ok=1
    echo "${#applied[@]} applied, ${#pending[@]} waiting"
    for name in "${pending[@]}"; do echo "  waiting: $name"; done
    exit $ok ;;
  apply)
    db=${DB_CONTAINER:-$(container mariadb)}
    apply ;;
  rehearse)
    rehearse ;;
  *)
    echo "usage: ./migrate.sh status | apply | rehearse" >&2; exit 2 ;;
esac
