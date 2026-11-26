#!/usr/bin/env bash
# borg-prune.sh: tidy one borg repository, from the side that is allowed to delete: your own computer.
# Chapter 12, tier 2. The machines being backed up can only add; this is the one place old archives go away.
#
#   borg-prune.sh REPO           look: the archives, how old the newest is, and what the tidy would remove
#   borg-prune.sh REPO --apply   look, then remove those archives and free their space
#
# REPO is the repository's address, for example ssh://borg@STORAGE/./repos/game. The SSH key you reach it with
# must be the one the storage machine lets delete (its line in authorized_keys has no --append-only).
# The passphrase is asked for once, unless BORG_PASSPHRASE or BORG_PASSCOMMAND is set.
#
# Settings, from the environment:
#   KEEP_DAILY, KEEP_WEEKLY, KEEP_MONTHLY   what to keep (default 14, 8, 12)
#   MAX_REMOVE   refuse to remove more archives than this in one go (default 40)
#   MAX_AGE_H    warn when the newest archive is older than this many hours (default 36)
#   STATE_DIR    where the list of archives seen last time is kept (default ~/.local/state/nwn-borg)
#
# Why it remembers: between two tidies the machines only ever add archives. So if an archive this script saw
# last time is gone, something deleted it. A borg repository in append-only mode can still be wound back to
# before that deletion, but only until someone frees the space. This script stops before freeing anything, so
# you can look first.
set -euo pipefail
REPO=${1:?usage: borg-prune.sh REPO [--apply]}
APPLY=${2:-}
KEEP=(--keep-daily "${KEEP_DAILY:-14}" --keep-weekly "${KEEP_WEEKLY:-8}" --keep-monthly "${KEEP_MONTHLY:-12}")
MAX_REMOVE=${MAX_REMOVE:-40}
MAX_AGE_H=${MAX_AGE_H:-36}
STATE_DIR=${STATE_DIR:-$HOME/.local/state/nwn-borg}
mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"
state="$STATE_DIR/$(printf '%s' "$REPO" | tr -c 'A-Za-z0-9._-' '_').archives"
export BORG_REPO=$REPO

if [ -z "${BORG_PASSPHRASE:-}" ] && [ -z "${BORG_PASSCOMMAND:-}" ]; then
  read -r -s -p "passphrase for $REPO: " BORG_PASSPHRASE; echo
  export BORG_PASSPHRASE
fi

now=$(borg list --lock-wait 600 --format '{archive} {id}{NL}' | sort)
count=$(printf '%s\n' "$now" | grep -c . || true)
[ "$count" -ge 1 ] || { echo "the repository has no archives" >&2; exit 2; }
echo "$count archives"

# 1. Has anything gone missing since last time?
if [ -s "$state" ]; then
  missing=$(comm -23 "$state" <(printf '%s\n' "$now"))
  if [ -n "$missing" ]; then
    echo "STOP: these archives were there last time and are gone now:" >&2
    printf '%s\n' "$missing" | cut -d' ' -f1 | sed 's/^/  /' >&2
    echo "Nothing was removed. Chapter 12, step 'If an archive has gone missing', says what to do." >&2
    exit 3
  fi
fi

# 2. How fresh is the newest?
newest=$(borg list --lock-wait 600 --last 1 --format '{archive} {time:%s}')
age_h=$(( ($(date +%s) - ${newest##* }) / 3600 ))
echo "newest: ${newest% *}, ${age_h} hours old"
[ "$age_h" -le "$MAX_AGE_H" ] || echo "WARNING: the newest backup is more than $MAX_AGE_H hours old"

# 3. What the policy would remove.
would=$(borg prune --dry-run --list --lock-wait 600 "${KEEP[@]}" 2>&1 | grep '^Would prune' || true)
n=$(printf '%s\n' "$would" | grep -c . || true)
echo "the policy would remove $n:"
[ "$n" = 0 ] || printf '%s\n' "$would" | sed 's/^/  /'
printf '%s\n' "$now" > "$state"

[ "$APPLY" = --apply ] || { echo "nothing removed (add --apply to remove them)"; exit 0; }
[ "$n" -le "$MAX_REMOVE" ] || { echo "REFUSING: $n is more than MAX_REMOVE ($MAX_REMOVE)" >&2; exit 3; }
[ "$n" -gt 0 ] || exit 0

# 4. Remove, then free the space. Only a key without --append-only frees anything.
borg prune --lock-wait 600 "${KEEP[@]}"
borg compact --lock-wait 600
borg list --lock-wait 600 --format '{archive} {id}{NL}' | sort > "$state"
echo "removed $n; $(grep -c . "$state") archives remain"
