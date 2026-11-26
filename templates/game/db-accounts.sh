#!/usr/bin/env bash
# Database accounts for services outside the game: websites, bots, reports (chapter 5, tier 3).
#
#   ./db-accounts.sh reader NAME FROM     make NAME, which may only read the game's tables, and only from address FROM
#   ./db-accounts.sh queue NAME FROM      make NAME, which may only add jobs to work_queue and read that table
#   ./db-accounts.sh sync [--dry-run]     bring the readers' rights in step with the tables (the timer runs this)
#   ./db-accounts.sh show NAME            what NAME may do
#   ./db-accounts.sh drop NAME            remove NAME
#
# reader and queue read the new account's password from the first line of their input, so it is never on a
# command line: at least 16 letters, digits, - or _ (openssl rand -hex 16 makes a good one).
#
# Run it from the game folder, as the deploy user. It uses the database administrator's password from db.env,
# which never leaves this machine: the administrator may only log in from inside the database's own container.
#
# Readers get their rights through one role, game_reader, so a single "sync" keeps every reader up to date:
# SELECT on every table of the game's database, and on a table with a private column, SELECT on every other
# column only. A column is private when its name matches DENY_COLUMNS. Nothing in other databases, no writes,
# at most MAX_CONNECTIONS connections at a time, and any query running longer than MAX_SECONDS is stopped, so a
# slow report can't hold up the game.
set -euo pipefail
cd "$(dirname "$0")"

DENY_COLUMNS=${DENY_COLUMNS:-'(^|_)(ip|ip_address|cdkey|public_cdkey|password|passwd|token|secret|email|api_key)$'}
MAX_CONNECTIONS=${MAX_CONNECTIONS:-5}
MAX_SECONDS=${MAX_SECONDS:-10}

exec 9<"$0"
# One at a time; a second waits for the first (the timer may be running a sync).
flock -w 60 9 || { echo "another db-accounts.sh has been running for a minute; try again later" >&2; exit 1; }

ids=$(docker ps -q --filter label=com.docker.compose.service=mariadb)
[ "$(printf '%s' "$ids" | grep -c .)" = 1 ] || { echo "expected one running mariadb container" >&2; exit 1; }
db=$ids
MYSQL_PWD=$(sed -n 's/^MARIADB_ROOT_PASSWORD=//p' db.env)
[ -n "$MYSQL_PWD" ] || { echo "no MARIADB_ROOT_PASSWORD in db.env" >&2; exit 1; }
export MYSQL_PWD
schema=$(docker exec "$db" printenv MARIADB_DATABASE)

# SQL on stdin, as the administrator. The password goes through the environment, never a command line.
sql() { docker exec -i -e MYSQL_PWD "$db" mariadb -uroot --batch --skip-column-names "$@"; }

check_name() { [[ $1 =~ ^[a-z][a-z0-9_]{2,31}$ ]] || { echo "an account name is 3 to 32 lowercase letters, digits or _" >&2; exit 2; }; }
check_from() { [[ $1 =~ ^[0-9.%]+$ ]] || { echo "FROM is the address the service connects from, like 10.77.0.1" >&2; exit 2; }; }
read_password() {
  IFS= read -r pw || true
  [[ $pw =~ ^[A-Za-z0-9_-]{16,}$ ]] || { echo "give the password on the first line of input: 16 or more letters, digits, - or _" >&2; exit 2; }
}
exists() { [ "$(echo "SELECT COUNT(*) FROM mysql.user WHERE User = '$1';" | sql)" != 0 ]; }
# Only accounts this script made: show and drop never touch the game's own account or the administrator.
ours() {
  exists "$1" || { echo "there is no account $1" >&2; exit 1; }
  [ "$(echo "SELECT COUNT(*) FROM mysql.user WHERE User = '$1' AND default_role IN ('game_reader', 'game_queue');" | sql)" != 0 ] ||
    { echo "$1 was not made by this script; leaving it alone" >&2; exit 1; }
}

make_account() { # name from role
  if exists "$1"; then echo "$1 exists already: drop it first to make it again" >&2; exit 1; fi
  sql <<SQL
CREATE USER '$1'@'$2' IDENTIFIED BY '$pw' WITH MAX_USER_CONNECTIONS $MAX_CONNECTIONS MAX_STATEMENT_TIME $MAX_SECONDS;
GRANT $3 TO '$1'@'$2';
SET DEFAULT ROLE $3 FOR '$1'@'$2';
SQL
  echo "made $1, which may log in from $2 only"
}

sync() { # --dry-run only prints
  local stmts; stmts=$(plan)
  [ -n "$stmts" ] || { echo "the readers' rights are in step with the tables"; return 0; }
  echo "$stmts"
  [ "${1:-}" = --dry-run ] && return 0
  printf '%s\n' "$stmts" | sql
  echo "applied $(printf '%s\n' "$stmts" | wc -l) change(s)"
}

# The statements that bring game_reader in step with the tables, one per line. Empty when it is in step.
plan() {
  sql mysql <<SQL
CREATE ROLE IF NOT EXISTS game_reader;
SET @deny = '$DENY_COLUMNS';
SET SESSION group_concat_max_len = 1000000;
CREATE TEMPORARY TABLE private (t VARCHAR(64) COLLATE utf8mb3_general_ci PRIMARY KEY)
  SELECT DISTINCT table_name AS t FROM information_schema.columns
  WHERE table_schema = '$schema' AND column_name REGEXP @deny;
-- A whole-table right on a table that now has a private column: take it back (the columns get theirs below).
SELECT CONCAT('REVOKE SELECT ON \`$schema\`.\`', p.Table_name, '\` FROM game_reader;')
  FROM mysql.tables_priv p JOIN private ON private.t = p.Table_name
  WHERE p.User = 'game_reader' AND p.Host = '' AND p.Db = '$schema' AND FIND_IN_SET('Select', p.Table_priv);
-- A right on a private column: take it back.
SELECT CONCAT('REVOKE SELECT (\`', p.Column_name, '\`) ON \`$schema\`.\`', p.Table_name, '\` FROM game_reader;')
  FROM mysql.columns_priv p
  WHERE p.User = 'game_reader' AND p.Host = '' AND p.Db = '$schema' AND p.Column_name REGEXP @deny;
-- A table with no private column and no right yet: the whole table.
SELECT CONCAT('GRANT SELECT ON \`$schema\`.\`', t.table_name, '\` TO game_reader;')
  FROM information_schema.tables t
  WHERE t.table_schema = '$schema' AND t.table_name NOT IN (SELECT t FROM private)
    AND NOT EXISTS (SELECT 1 FROM mysql.tables_priv p WHERE p.User = 'game_reader' AND p.Host = ''
      AND p.Db = '$schema' AND p.Table_name = t.table_name AND FIND_IN_SET('Select', p.Table_priv));
-- A table with a private column: every other column that has no right yet.
SELECT CONCAT('GRANT SELECT (', GROUP_CONCAT(CONCAT('\`', c.column_name, '\`') ORDER BY c.ordinal_position),
              ') ON \`$schema\`.\`', c.table_name, '\` TO game_reader;')
  FROM information_schema.columns c JOIN private ON private.t = c.table_name
  WHERE c.table_schema = '$schema' AND c.column_name NOT REGEXP @deny
    AND NOT EXISTS (SELECT 1 FROM mysql.columns_priv p WHERE p.User = 'game_reader' AND p.Host = ''
      AND p.Db = '$schema' AND p.Table_name = c.table_name AND p.Column_name = c.column_name)
  GROUP BY c.table_name;
SQL
}

case ${1:-} in
  reader)
    [ $# = 3 ] || { echo "usage: ./db-accounts.sh reader NAME FROM" >&2; exit 2; }
    check_name "$2"; check_from "$3"; read_password
    sync > /dev/null
    make_account "$2" "$3" game_reader ;;
  queue)
    [ $# = 3 ] || { echo "usage: ./db-accounts.sh queue NAME FROM" >&2; exit 2; }
    check_name "$2"; check_from "$3"; read_password
    [ "$(echo "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$schema' AND table_name = 'work_queue';" | sql)" = 1 ] ||
      { echo "there is no work_queue table yet: release its migration first" >&2; exit 1; }
    sql <<SQL
CREATE ROLE IF NOT EXISTS game_queue;
GRANT SELECT, INSERT (kind, args, added_by) ON \`$schema\`.work_queue TO game_queue;
SQL
    make_account "$2" "$3" game_queue ;;
  sync)
    sync "${2:-}" ;;
  show)
    [ $# = 2 ] || { echo "usage: ./db-accounts.sh show NAME" >&2; exit 2; }
    check_name "$2"; ours "$2"
    host=$(echo "SELECT Host FROM mysql.user WHERE User = '$2' LIMIT 1;" | sql)
    echo "SHOW GRANTS FOR '$2'@'$host';" | sql | sed 's/ IDENTIFIED BY PASSWORD [^ ]*//'
    role=$(echo "SELECT default_role FROM mysql.user WHERE User = '$2' AND Host = '$host';" | sql)
    if [ -n "$role" ]; then echo "SHOW GRANTS FOR $role;" | sql | grep -v "^GRANT USAGE"; fi ;;
  drop)
    [ $# = 2 ] || { echo "usage: ./db-accounts.sh drop NAME" >&2; exit 2; }
    check_name "$2"; ours "$2"
    echo "SELECT CONCAT('DROP USER \`', User, '\`@\`', Host, '\`;') FROM mysql.user WHERE User = '$2';" | sql | sql
    echo "removed $2" ;;
  *)
    echo "usage: ./db-accounts.sh reader|queue NAME FROM | sync [--dry-run] | show NAME | drop NAME" >&2; exit 2 ;;
esac
