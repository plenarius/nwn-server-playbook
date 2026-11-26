#!/usr/bin/env bash
# Fresh dumps of the sites' databases (chapter 11, tier 3: Authentik, the forum, the wiki), for nwn-borg-backup on
# the control host. Install it in /etc/nwn-borg/hooks.d/. Every running container with the labels backup.dump
# (postgres or mariadb) and backup.name gets /var/backups/nwn-borg/site-<name>.sql, plain SQL without dates in it,
# so borg stores only what changed. A dump replaces the previous one only when it is complete.
#
# Authentik's dump is useless without its AUTHENTIK_SECRET_KEY, and the forum's and wiki's without their settings:
# those live in Coolify's environment variables, which chapter 12's Coolify database dump keeps.
set -euo pipefail
umask 077
OUT=/var/backups/nwn-borg
mkdir -p "$OUT"
fail=0

for id in $(docker ps -q --filter label=backup.dump --filter label=backup.name); do
  kind=$(docker inspect -f '{{index .Config.Labels "backup.dump"}}' "$id")
  name=$(docker inspect -f '{{index .Config.Labels "backup.name"}}' "$id")
  [[ $name =~ ^[a-z0-9-]+$ ]] || { echo "skipping a container with the odd backup.name '$name'" >&2; fail=1; continue; }
  f="$OUT/site-$name.sql"
  case $kind in
    postgres)
      # The whole database, with no owners or permissions in it, so it loads into a fresh one.
      docker exec "$id" sh -c 'pg_dump --no-owner --no-acl -U "$POSTGRES_USER" "$POSTGRES_DB"' > "$f.new" &&
        tail -n 6 "$f.new" | grep -q 'PostgreSQL database dump complete' ;;
    mariadb)
      docker exec "$id" sh -c \
        'mariadb-dump -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" --single-transaction --routines --skip-dump-date "$MARIADB_DATABASE"' \
        > "$f.new" && tail -n 1 "$f.new" | grep -q 'Dump completed' ;;
    *) echo "skipping $name: backup.dump must be postgres or mariadb, not '$kind'" >&2; false ;;
  esac && mv -f "$f.new" "$f" || { rm -f "$f.new"; echo "the dump of $name failed" >&2; fail=1; }
done
exit $fail
