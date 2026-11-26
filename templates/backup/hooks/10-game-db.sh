#!/usr/bin/env bash
# A fresh dump of the game's database, for nwn-borg-backup. Install it in /etc/nwn-borg/hooks.d/.
# It writes /var/backups/nwn-borg/game-db.sql in plain SQL, without the date in it, so borg recognises the parts
# that didn't change since last night and stores only the rest. The previous dump is replaced only by a complete one.
set -euo pipefail
umask 077
OUT=/var/backups/nwn-borg
mkdir -p "$OUT"

# The database container, found by the name the compose file gives it: plain Docker Compose (tier 1) or Coolify.
ids=$(docker ps -q --filter "label=com.docker.compose.service=mariadb")
[ "$(printf '%s' "$ids" | grep -c .)" = 1 ] || { echo "expected one running 'mariadb' container" >&2; exit 1; }

docker exec -i "$ids" sh -c \
  'mariadb-dump -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" --single-transaction --routines --skip-dump-date "$MARIADB_DATABASE"' \
  > "$OUT/game-db.sql.new" || { rm -f "$OUT/game-db.sql.new"; echo "the dump failed" >&2; exit 1; }
tail -n 1 "$OUT/game-db.sql.new" | grep -q 'Dump completed' ||
  { rm -f "$OUT/game-db.sql.new"; echo "the dump is not complete" >&2; exit 1; }
mv -f "$OUT/game-db.sql.new" "$OUT/game-db.sql"
