#!/usr/bin/env bash
# Sends the newest nightly database dump of the live game, for copy-db.sh on the control host (chapter 14).
# It goes in ~/game on the game host, beside backup.sh and its backups/ folder.
#
# The control host's key runs this and nothing else: its line in ~/.ssh/authorized_keys on the game host is
#   command="/home/nwn/game/send-dump.sh",from="10.0.0.1",restrict ssh-ed25519 AAAA... dev-copy-db
# with from= set to the control host's private address. Whatever that key asks for, it gets the dump, and only if
# the dump is recent. It reads one file and changes nothing.
set -euo pipefail
cd "$(dirname "$0")"
MAX_AGE_HOURS=${MAX_AGE_HOURS:-36}

backup=$(find backups -mindepth 1 -maxdepth 1 -type d -name '[0-9]*-[0-9]*' | sort | tail -n 1)
[ -n "$backup" ] && [ -f "$backup/db.sql.gz" ] || { echo "no backup of the live game found in $PWD/backups" >&2; exit 1; }
age=$(( ($(date +%s) - $(stat -c %Y "$backup/db.sql.gz")) / 3600 ))
[ "$age" -lt "$MAX_AGE_HOURS" ] ||
  { echo "the newest backup, $(basename "$backup"), is $age hours old; is the nightly backup running?" >&2; exit 1; }
echo "sending $(basename "$backup") ($age hours old)" >&2
cat "$backup/db.sql.gz"
