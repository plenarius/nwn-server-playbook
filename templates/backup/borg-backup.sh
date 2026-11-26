#!/usr/bin/env bash
# borg-backup.sh: one encrypted backup of this machine into its own borg repository on another machine.
# Chapter 12, tier 2 installs it as /usr/local/sbin/nwn-borg-backup, and borg-backup.timer starts it every night.
#
#   nwn-borg-backup                make a backup now
#   nwn-borg-backup --test-alert   send a test message to the alert webhook, if there is one
#   nwn-borg-backup borg ARGS...   run any borg command against this machine's repository, for example
#                                  "nwn-borg-backup borg list" or "nwn-borg-backup borg extract ::ARCHIVE PATH"
#
# Everything it needs is in /etc/nwn-borg, readable by root only:
#   borg.conf     NAME, REPO and PATHS (see borg.conf.example); optionally EXCLUDE and BORG_REMOTE_PATH
#   passphrase    the repository's passphrase, one line. Keep a copy somewhere else: without it the backups are noise
#   ssh-key       the SSH key the storage machine knows. There it may only add to this one repository
#   known_hosts   the storage machine's host key, so a machine pretending to be it is refused
#   hooks.d/*.sh  run first, in name order; each makes something fresh to back up, such as a database dump
#   alert-webhook optional: a Discord-style webhook address, told when a backup fails
#
# If a hook fails, a path in PATHS is missing, or borg reports an error, no archive is made, the webhook is told,
# and the script exits with an error. borg's exit code 1 is a warning (usually a file changed while it was read):
# the archive is made, and the warning is printed.
set -uo pipefail
umask 077
DIR=${NWN_BORG_DIR:-/etc/nwn-borg}
[ "$(id -u)" = 0 ] || { echo "run this as root" >&2; exit 2; }
[ -r "$DIR/borg.conf" ] || { echo "$DIR/borg.conf is missing" >&2; exit 2; }
# shellcheck source=/dev/null
. "$DIR/borg.conf"
: "${NAME:?set NAME in $DIR/borg.conf}" "${REPO:?set REPO in $DIR/borg.conf}"

export BORG_REPO=$REPO
export BORG_PASSCOMMAND="cat $DIR/passphrase"
export BORG_RSH="ssh -i $DIR/ssh-key -o IdentitiesOnly=yes -o UserKnownHostsFile=$DIR/known_hosts -o StrictHostKeyChecking=yes -o BatchMode=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=10"
[ -n "${BORG_REMOTE_PATH:-}" ] && export BORG_REMOTE_PATH

alert() {
  [ -r "$DIR/alert-webhook" ] || return 0
  python3 -c 'import json,sys; print(json.dumps({"content": sys.argv[1]}))' "$1" |
    curl -fsS -m 15 -H 'Content-Type: application/json' --data-binary @- "$(tr -d '\n' < "$DIR/alert-webhook")" > /dev/null ||
    echo "could not reach the alert webhook" >&2
}
fail() {
  echo "$*" >&2
  alert "Backup of $NAME ($(hostname)) FAILED: $*"
  exit 2
}

case "${1:-}" in
  --test-alert) alert "Test message from the backup of $NAME ($(hostname)). Nothing is wrong."; echo "sent"; exit 0 ;;
  borg) shift; exec borg "$@" ;;
  "") ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac

[ -s "$DIR/passphrase" ] || fail "$DIR/passphrase is missing or empty"

# 1. The hooks: fresh copies of anything that can't be read safely while it runs, such as a database.
for hook in "$DIR"/hooks.d/*.sh; do
  [ -x "$hook" ] || continue
  "$hook" || fail "the hook $(basename "$hook") failed"
done

# 2. Every path must be there. A path that has quietly moved would otherwise leave a hole in every backup.
for p in "${PATHS[@]}"; do
  [ -e "$p" ] || fail "$p is in PATHS but does not exist"
done

# 3. The archive. Its name says which machine and when.
excl=()
for e in "${EXCLUDE[@]:-}"; do [ -n "$e" ] && excl+=(--exclude "$e"); done
echo "$(date -u +%FT%TZ) backing up $NAME"
borg create --lock-wait 600 --stats --compression zstd,6 --exclude-caches "${excl[@]}" \
  "::$NAME-{now:%Y-%m-%dT%H%M%S}" "${PATHS[@]}"
rc=$?
[ $rc -ge 2 ] && fail "borg create ended with exit code $rc; see journalctl -u borg-backup.service"
[ $rc = 1 ] && echo "borg finished with a warning (exit code 1); the archive was made"
echo "$(date -u +%FT%TZ) backup made: $(borg list --lock-wait 600 --last 1 --format '{archive}')"
