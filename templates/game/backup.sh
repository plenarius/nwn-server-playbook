#!/usr/bin/env bash
# Makes one backup of the game server, into backups/<date-and-time>/ beside this script:
#   db.sql.gz       everything in the game's database
#   files.tar.gz    the characters, the game's own small databases, its settings and key, and your two settings files
# Run it as root from the game folder (the nightly timer does), or by hand:  sudo ./backup.sh
#
# A backup folder appears only when both files were written completely. If anything fails, nothing new
# appears, nothing old is touched, and the script exits with an error. Old backups are removed only after
# a new one succeeded.
#
# Settings, from the environment:
#   KEEP_DAYS   remove backups older than this many days (default 14)
#   KEEP_MIN    but always keep at least this many of the newest (default 3)
set -euo pipefail
umask 077
cd "$(dirname "$0")"

KEEP_DAYS=${KEEP_DAYS:-14}
KEEP_MIN=${KEEP_MIN:-3}

# The game's containers, found by the name the compose file gives them. This works whether plain Docker Compose
# (tier 1) or Coolify (tier 2) started them.
container() {
  local ids; ids=$(docker ps -aq --filter "label=com.docker.compose.service=$1")
  [ "$(printf '%s' "$ids" | grep -c .)" = 1 ] || { echo "expected one '$1' container, found $(printf '%s' "$ids" | grep -c .)" >&2; exit 1; }
  echo "$ids"
}

stamp=$(date -u +%Y%m%d-%H%M%S)
tmp=backups/.unfinished-$stamp
mkdir -p "$tmp"
chmod 700 backups "$tmp"
trap 'rm -rf "$tmp"' EXIT

# 1. The database. The dump is taken as the game's own account, in one consistent snapshot.
db=$(container mariadb)
docker exec -i "$db" sh -c \
  'mariadb-dump -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" --single-transaction --routines "$MARIADB_DATABASE"' \
  | gzip > "$tmp/db.sql.gz"
# A complete dump ends with a line that says so. A cut-off one does not.
zcat "$tmp/db.sql.gz" | tail -n 1 | grep -q 'Dump completed' ||
  { echo "the database dump is not complete; no backup was made" >&2; exit 1; }

# 2. The files that exist nowhere else.
files=()
for f in home/servervault home/database home/settings.tml home/cryptographic_secret .env db.env; do
  [ -e "$f" ] && files+=("$f")
done
tar czf "$tmp/files.tar.gz" "${files[@]}"
tar tzf "$tmp/files.tar.gz" > /dev/null

# 3. Put it in place in one move, owned like the game folder so its owner can copy it away.
chown --reference=. backups
chown -R --reference=. "$tmp"
mv -T "$tmp" "backups/$stamp"
trap - EXIT
echo "backup made: backups/$stamp ($(du -sh "backups/$stamp" | cut -f1))"

# 4. Tidy up: older than KEEP_DAYS goes, but the newest KEEP_MIN always stay.
find backups -maxdepth 1 -type d -name '.unfinished-*' -mmin +60 -exec rm -rf {} +
find backups -maxdepth 1 -type d -name '[0-9]*-[0-9]*' | sort -r | tail -n +$((KEEP_MIN + 1)) | while read -r old; do
  if [ -n "$(find "$old" -maxdepth 0 -mtime +"$KEEP_DAYS")" ]; then
    rm -rf "$old"
    echo "removed old backup: $old"
  fi
done
