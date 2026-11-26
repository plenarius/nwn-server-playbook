#!/usr/bin/env bash
# Gives the dev server a scrubbed copy of the live game's database (chapter 14).
# Run it on the control host, as the deploy user, from the dev folder:  ~/dev/copy-db.sh --yes
# To check the dev database against scrub.list at any time, without copying:  ~/dev/copy-db.sh --check
#
# What it does, in order:
#   1. fetches the newest nightly dump from the game host over the private network, through a key that can do
#      nothing else (send-dump.sh on the game host);
#   2. loads it into a throwaway MariaDB with no network, whose data lives only in memory;
#   3. checks scrub.list against what is really there, applies it, and checks every rule held;
#   4. only then empties the dev server's database and fills it with the scrubbed copy, and starts the dev game.
# If anything fails, it stops before step 4 and the dev server keeps the database it had. The unscrubbed copy
# never reaches a disk on this machine or the dev server, and is gone when the script ends, however it ends.
# The dev server's characters are not touched: their folders are named after players' accounts.
set -euo pipefail
set -f  # no filename expansion: a rule's * means a whole table
umask 077
cd "$(dirname "$0")"

GAME=${GAME:-nwn@10.0.0.2}                  # the game host, by its private address
KEY=${KEY:-$HOME/.ssh/dev-copy-db}          # the key that runs send-dump.sh there
RULES=${RULES:-scrub.list}
# Column names that look private. Each one needs a rule in scrub.list, if only "keep".
PRIVATE_NAMES=${PRIVATE_NAMES:-'(^|_)ip(_|$)|ipaddr|ip_addr|cdkey|cd_key|public_key|password|passwd|email|e_mail|discord|steam|token|secret|account|login|username'}

container() { # the one container of this compose service
  local ids; ids=$(docker ps -aq --filter "label=com.docker.compose.service=$1")
  [ "$(printf '%s' "$ids" | grep -c .)" = 1 ] || { echo "expected one '$1' container, found $(printf '%s' "$ids" | grep -c .)" >&2; exit 1; }
  echo "$ids"
}
game=$(container dev-nwserver)
devdb=$(container dev-mariadb)

# The rules, read and checked for shape before anything is fetched.
[ -f "$RULES" ] || { echo "no $RULES here: copy scrub.list.example to $RULES and write your rules" >&2; exit 1; }
rules=()
while read -r t c w _; do
  [[ -z $t || $t == \#* ]] && continue
  [[ $t =~ ^[A-Za-z0-9_]+$ && $c =~ ^([A-Za-z0-9_]+|\*)$ ]] || { echo "$RULES: '$t $c' is not a table and a column" >&2; exit 1; }
  case $w in
    blank | null | pseudonym | keep) [ "$c" != '*' ] || { echo "$RULES: $t: '$w' needs a column, not *" >&2; exit 1; } ;;
    empty) [ "$c" = '*' ] || { echo "$RULES: $t: 'empty' is for a whole table; write * as the column" >&2; exit 1; } ;;
    *) echo "$RULES: '$t $c $w': what to do is blank, null, pseudonym, empty or keep" >&2; exit 1 ;;
  esac
  rules+=("$t $c $w")
done < "$RULES"

left_sql() { # counts the rows that still break rule "$1 $2 $3"
  case $3 in
    blank) echo "SELECT COUNT(*) FROM \`$1\` WHERE \`$2\` IS NOT NULL AND \`$2\` <> ''" ;;
    null) echo "SELECT COUNT(*) FROM \`$1\` WHERE \`$2\` IS NOT NULL" ;;
    pseudonym) echo "SELECT COUNT(*) FROM \`$1\` WHERE \`$2\` IS NOT NULL AND \`$2\` <> '' AND \`$2\` NOT REGEXP '^p[0-9a-f]{12}\$'" ;;
    empty) echo "SELECT COUNT(*) FROM \`$1\`" ;;
    keep) echo "SELECT 0" ;;
  esac
}
devsql() { docker exec -i "$devdb" sh -c 'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" '"$*"; }

# --check: every rule against the dev server's database as it is now, without copying anything.
if [ "${1:-}" = --check ]; then
  bad=0
  for r in "${rules[@]}"; do
    set -- $r; [ "$3" = keep ] && continue
    n=$(left_sql "$1" "$2" "$3" | devsql -N) || n=error
    echo "  $1.$2 ($3): $n left"; [ "$n" = 0 ] || bad=1
  done
  [ "$bad" = 0 ] && echo "the dev database keeps every rule" || { echo "the dev database breaks a rule" >&2; exit 1; }
  exit 0
fi

[ "${1:-}" = --yes ] || {
  echo "This replaces everything in the dev server's database with a scrubbed copy of the live one, and restarts"
  echo "the dev game. Builders on it are disconnected, and what they made in the database is gone."
  echo "Run it again with --yes to go ahead, or with --check to test the dev database against $RULES."
  exit 2
}

# 1 and 2. A throwaway database with no network and no disk, and the live dump loaded into it.
image=$(docker inspect -f '{{.Config.Image}}' "$devdb")
scrub=dev-scrub-$$
docker run -d --rm --name "$scrub" --network none --tmpfs /var/lib/mysql --tmpfs /work \
  -e MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=1 -e MARIADB_DATABASE=nwn "$image" > /dev/null
trap 'docker rm -f "$scrub" > /dev/null 2>&1' EXIT
for _ in $(seq 60); do docker exec "$scrub" healthcheck.sh --connect --innodb_initialized > /dev/null 2>&1 && break; sleep 1; done
q() { docker exec -i "$scrub" mariadb -uroot -N -B nwn; }

err=$(mktemp)
ssh -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes "$GAME" dump 2> "$err" | docker exec -i "$scrub" sh -c 'cat > /work/live.sql.gz' ||
  { cat "$err" >&2; echo "could not fetch the dump from $GAME" >&2; exit 1; }
from=$(sed -n 's/^sending \([0-9-]*\) .*/\1/p' "$err"); rm -f "$err"
[ -n "$from" ] || { echo "the game host did not say which backup it sent" >&2; exit 1; }
docker exec "$scrub" sh -c 'zcat /work/live.sql.gz | tail -n 1' | grep -q 'Dump completed' ||
  { echo "the dump from $from is not complete" >&2; exit 1; }
docker exec "$scrub" sh -c 'zcat /work/live.sql.gz | mariadb -uroot nwn && rm /work/live.sql.gz'
echo "live backup $from loaded into a throwaway database"

# 3. The rules, against what is really there.
columns=$(echo "SELECT CONCAT(table_name, ' ', column_name) FROM information_schema.columns WHERE table_schema = 'nwn'" | q)
has() { grep -qx -- "$1" <<< "$columns"; }
covered() { # is this table and column named by a rule?
  local r; for r in "${rules[@]}"; do
    set -- $r; [ "$1" = "$T" ] && { [ "$2" = "$C" ] || [ "$2" = '*' ]; } && return 0
  done; return 1
}
problems=0
for r in "${rules[@]}"; do
  set -- $r
  if [ "$2" = '*' ]; then grep -q "^$1 " <<< "$columns" || { echo "$RULES names table $1, which isn't there" >&2; problems=1; }
  else has "$1 $2" || { echo "$RULES names $1.$2, which isn't there" >&2; problems=1; }
  fi
done
while read -r T C; do
  [ -n "$T" ] || continue
  if [[ ${C,,} =~ $PRIVATE_NAMES ]] && ! covered; then
    echo "$T.$C looks private and has no rule in $RULES (blank, null, pseudonym, or keep if it is fine)" >&2; problems=1
  fi
done <<< "$columns"
[ "$problems" = 0 ] || { echo "nothing was changed; the dev server keeps the database it had" >&2; exit 1; }

# Apply, then check each rule held, from the data itself.
salt=$(openssl rand -hex 16)
left() { left_sql "$@" | q; }
for r in "${rules[@]}"; do
  set -- $r
  before=$(left "$1" "$2" "$3")
  case $3 in
    blank) echo "UPDATE \`$1\` SET \`$2\` = '' WHERE \`$2\` <> ''" | q ;;
    null) echo "UPDATE \`$1\` SET \`$2\` = NULL" | q ;;
    pseudonym) echo "SET @salt = '$salt'; UPDATE \`$1\` SET \`$2\` = CONCAT('p', LEFT(SHA2(CONCAT(@salt, \`$2\`), 256), 12)) WHERE \`$2\` <> ''" | q ;;
    empty) echo "DELETE FROM \`$1\`" | q ;;
    keep) ;;
  esac
  after=$(left "$1" "$2" "$3")
  [ "$after" = 0 ] || { echo "$1.$2 ($3): $after rows still hold a real value; nothing was copied" >&2; exit 1; }
  [ "$3" = keep ] && echo "  $1.$2: kept as it is" || echo "  $1.$2: $3, $before rows changed, 0 left"
done
salt=
docker exec "$scrub" sh -c 'mariadb-dump -uroot --single-transaction --routines nwn > /work/clean.sql && tail -n 1 /work/clean.sql' |
  grep -q 'Dump completed' || { echo "could not dump the scrubbed copy" >&2; exit 1; }
echo "scrubbed with ${#rules[@]} rules from $RULES, every rule checked"

# 4. Into the dev server, which stops while its database is swapped.
docker stop -t 30 "$game" > /dev/null && echo "dev game stopped"
echo "SELECT CONCAT('DROP TABLE IF EXISTS \`', table_name, '\`;') FROM information_schema.tables WHERE table_schema = DATABASE();" \
  | devsql -N | { echo 'SET FOREIGN_KEY_CHECKS=0;'; cat; } | devsql
docker exec "$scrub" cat /work/clean.sql | devsql
echo "dev database filled from live backup $from, scrubbed"
printf '%s from live backup %s, scrubbed by %s (sha256 %s)\n' "$(date -u +%FT%TZ)" "$from" "$RULES" \
  "$(sha256sum "$RULES" | cut -c1-12)" > db-copied.txt
chmod 644 db-copied.txt
docker start "$game" > /dev/null
for _ in $(seq 100); do [ "$(docker inspect -f '{{.State.Health.Status}}' "$game")" = healthy ] && break; sleep 3; done
[ "$(docker inspect -f '{{.State.Health.Status}}' "$game")" = healthy ] ||
  { echo "the dev game did not become healthy; look at: docker logs --tail 50 $game" >&2; exit 1; }
echo "dev server is healthy on the copied database"
