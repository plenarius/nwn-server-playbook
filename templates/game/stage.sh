#!/usr/bin/env bash
# Puts a new module on the staging copy of the game, with a fresh copy of the live game's data.
#
#   ssh nwn@GAME "stage v1.4.0" < mymodule.mod
#
# CI runs it through a key that can run this and nothing else (chapter 6, tier 2): the key's line in
# ~/.ssh/authorized_keys starts with  command="sudo -n /home/nwn/staging/stage.sh \"$SSH_ORIGINAL_COMMAND\"",restrict
# You can also run it by hand on the game host:  sudo ./stage.sh "stage v1.4.0" < mymodule.mod
#
# What it does, in order:
#   1. checks the request and the file (a module, under 1 GB);
#   2. stops the staging game, and fills the staging database and character vault from the live game's latest
#      backup (chapter 12), so staging plays with yesterday's world;
#   3. installs the module under the name the staging game loads, starts it, and waits until it is healthy;
#   4. writes what is staged, with the file's checksum, to staged.txt beside this script.
# The live game is never touched. It only reads the live game's backups.
set -euo pipefail
umask 027
cd "$(dirname "$0")"
GAME_DIR=${GAME_DIR:-../game}

request=${1:-}
[[ $request =~ ^stage\ (v[0-9A-Za-z._-]{1,40})$ ]] || { echo "usage: stage vX.Y.Z  (got: ${request:0:60})" >&2; exit 2; }
version=${BASH_REMATCH[1]}

container() { # the one running container of this compose service
  local ids; ids=$(docker ps -aq --filter "label=com.docker.compose.service=$1")
  [ "$(printf '%s' "$ids" | grep -c .)" = 1 ] || { echo "expected one '$1' container, found $(printf '%s' "$ids" | grep -c .)" >&2; exit 1; }
  echo "$ids"
}
game=$(container staging-nwserver)
db=$(container staging-mariadb)
module=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$game" | sed -n 's/^NWN_MODULE=//p')
[[ $module =~ ^[A-Za-z0-9_]{1,16}$ ]] || { echo "the staging game has no usable NWN_MODULE setting" >&2; exit 1; }

# 1. The file, from standard input.
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
head -c 1073741825 > "$tmp/new.mod"
[ "$(stat -c %s "$tmp/new.mod")" -le 1073741824 ] || { echo "the file is over 1 GB" >&2; exit 1; }
[ "$(head -c 8 "$tmp/new.mod")" = "MOD V1.0" ] || { echo "that is not a module file" >&2; exit 1; }
sum=$(sha256sum "$tmp/new.mod" | cut -d' ' -f1)
echo "received $version: $(stat -c %s "$tmp/new.mod") bytes, sha256 $sum"

# 2. Yesterday's world.
backup=$(find "$GAME_DIR/backups" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*-[0-9]*' | sort | tail -n 1)
[ -n "$backup" ] && [ -f "$backup/db.sql.gz" ] || { echo "no backup of the live game found in $GAME_DIR/backups" >&2; exit 1; }
docker stop "$game" > /dev/null && echo "staging game stopped"
sql() { docker exec -i "$db" sh -c 'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" '"$*"; }
# Empty the staging database first, so that nothing staging made last time is left over.
echo "SELECT CONCAT('DROP TABLE IF EXISTS \`', table_name, '\`;') FROM information_schema.tables WHERE table_schema = DATABASE();" \
  | sql -N | { echo 'SET FOREIGN_KEY_CHECKS=0;'; cat; } | sql
zcat "$backup/db.sql.gz" | sql
echo "staging database filled from $backup"
if tar tzf "$backup/files.tar.gz" home/servervault > /dev/null 2>&1; then
  rm -rf home/servervault && tar xzf "$backup/files.tar.gz" home/servervault
  echo "staging characters copied from $backup"
fi

# 3. The module, then the game.
mkdir -p home/modules
cp "$tmp/new.mod" "home/modules/$module.mod.new" && mv -f "home/modules/$module.mod.new" "home/modules/$module.mod"
docker start "$game" > /dev/null && echo "staging game started with $module.mod"
for _ in $(seq 90); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' "$game")" = healthy ] && break
  sleep 2
done
[ "$(docker inspect -f '{{.State.Health.Status}}' "$game")" = healthy ] ||
  { echo "the staging game did not become healthy within three minutes; look at: docker logs --tail 50 $game" >&2; exit 1; }

# 4. The record.
printf '%s %s sha256 %s from backup %s\n' "$(date -u +%FT%TZ)" "$version" "$sum" "$(basename "$backup")" > staged.txt
chmod 644 staged.txt  # readable by the deploy user, who checks it before going live
echo "staging is healthy with $version"
