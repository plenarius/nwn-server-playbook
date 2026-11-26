#!/usr/bin/env bash
# A fresh dump of Coolify's own database, for nwn-borg-backup on the control host. Install it in
# /etc/nwn-borg/hooks.d/. It writes /var/backups/nwn-borg/coolify-db.dmp in pg_dump's custom format, which is
# what Coolify's restore instructions load, uncompressed so that borg can find what didn't change since last night.
# The dump is worthless without Coolify's APP_KEY, which is in /data/coolify/source/.env: back that file up too.
set -euo pipefail
umask 077
OUT=/var/backups/nwn-borg
mkdir -p "$OUT"

docker exec coolify-db pg_dump --format=custom --compress=0 --no-acl --no-owner --username=coolify coolify \
  > "$OUT/coolify-db.dmp.new" || { rm -f "$OUT/coolify-db.dmp.new"; echo "the dump failed" >&2; exit 1; }
# A custom-format dump that can be listed from start to end is complete.
docker exec -i coolify-db pg_restore --list < "$OUT/coolify-db.dmp.new" > /dev/null ||
  { rm -f "$OUT/coolify-db.dmp.new"; echo "the dump can't be read back" >&2; exit 1; }
mv -f "$OUT/coolify-db.dmp.new" "$OUT/coolify-db.dmp"
