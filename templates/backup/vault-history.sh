#!/usr/bin/env bash
# vault-history.sh: the character vault's history in git. Chapter 12, tier 3 installs it as
# /usr/local/sbin/nwn-vault-history, and vault-history.timer runs it every 30 minutes.
#
#   nwn-vault-history                      copy the vault, commit what changed, push it
#   nwn-vault-history log FILE             every saved version of one character, newest first
#   nwn-vault-history restore FILE WHEN    put one character back as it was at WHEN: a commit from "log", or a
#                                          time such as "2026-11-26 14:00" (the last version saved before it)
#
# FILE is the character's path inside the vault, as "log" and the commits show it: FOLDER/NAME.bic.
#
# The history is a git repository of its own, HISTORY, holding a copy of the vault. git never works in the live
# vault: a run copies it first, leaving out any file changed in the last SETTLE seconds, which the game may still
# be writing (the next run takes it). Only "restore" writes into the vault, one file, and keeps the file it replaces.
#
# After each run that pushed (or had nothing new), it writes the time to HISTORY.ok. chapter 13's watchdog reads
# that through watchdog-report.sh, and tells you when the history has stopped moving.
#
# Settings, from /etc/nwn-vault-history.conf if it exists (a shell file), or these defaults:
set -euo pipefail
umask 077
GAME=/home/nwn/game
VAULT=$GAME/home/servervault
HISTORY=$GAME/vault-history
KEY=/root/.ssh/vault-history          # the deploy key that may push to the history's repository, and nothing else
KNOWN_HOSTS=/root/.ssh/vault-history.known_hosts
BRANCH=main
SETTLE=10
[ -r /etc/nwn-vault-history.conf ] && . /etc/nwn-vault-history.conf

[ "$(id -u)" = 0 ] || { echo "run this as root" >&2; exit 2; }
export GIT_SSH_COMMAND="ssh -i $KEY -o IdentitiesOnly=yes -o UserKnownHostsFile=$KNOWN_HOSTS -o StrictHostKeyChecking=yes -o BatchMode=yes"
g() { git -C "$HISTORY" "$@"; }
check_path() {
  case "$1" in
    */*.bic) ;;
    *) echo "give the character as FOLDER/NAME.bic, as 'log' and the commits show it" >&2; exit 2 ;;
  esac
  case "$1" in /*|*..*) echo "a path inside the vault, please" >&2; exit 2 ;; esac
}

case "${1:-}" in
  log)
    check_path "${2:?log FOLDER/NAME.bic}"
    g log --format='%h  %ad  %s' --date=format-local:'%Y-%m-%d %H:%M UTC' -- "$2"
    exit 0 ;;
  restore)
    file=${2:?restore FOLDER/NAME.bic WHEN}; when=${3:?restore FOLDER/NAME.bic WHEN}
    check_path "$file"
    if g rev-parse -q --verify "$when^{commit}" > /dev/null; then
      rev=$(g rev-parse --short "$when^{commit}")
    else
      rev=$(TZ=UTC g rev-list -1 --before="$when UTC" HEAD -- "$file" | cut -c1-7)
      [ -n "$rev" ] || { echo "no version of $file saved before $when" >&2; exit 1; }
    fi
    g cat-file -e "$rev:$file" 2> /dev/null || { echo "$file is not in commit $rev" >&2; exit 1; }
    stamp=$(date -u +%Y%m%d-%H%M%S)
    if [ -e "$VAULT/$file" ]; then
      # The current file, kept beside the history (not in the vault, where the game would see it).
      mkdir -p "$HISTORY.replaced"
      cp -p "$VAULT/$file" "$HISTORY.replaced/$(echo "$file" | tr / _).$stamp"
      owner=$(stat -c %u:%g "$VAULT/$file")
    else
      mkdir -p "$VAULT/$(dirname "$file")"
      owner=$(stat -c %u:%g "$VAULT")
    fi
    g show "$rev:$file" > "$VAULT/$file.restoring"
    chown "$owner" "$VAULT/$file.restoring"; chmod 644 "$VAULT/$file.restoring"
    mv "$VAULT/$file.restoring" "$VAULT/$file"
    echo "restored $file as it was in $rev ($(g log -1 --format=%ad --date=format-local:'%Y-%m-%d %H:%M UTC' "$rev"))"
    [ -d "$HISTORY.replaced" ] && echo "the file it replaced: $HISTORY.replaced/$(echo "$file" | tr / _).$stamp"
    echo "the next run records the restore in the history"
    exit 0 ;;
  "") ;;
  *) echo "unknown command: $1 (log, restore, or nothing to make a commit)" >&2; exit 2 ;;
esac

[ -d "$VAULT" ] || { echo "$VAULT does not exist" >&2; exit 2; }
[ -d "$HISTORY/.git" ] || { echo "$HISTORY is not a git repository yet: see chapter 12, tier 3, step 24" >&2; exit 2; }
exec 9> "$HISTORY.lock"
flock -n 9 || { echo "another run is still going" >&2; exit 1; }

# 1. Copy the vault into the history's folder, except files the game wrote in the last few seconds. A deleted
#    character is deleted in the copy too, so the history records the deletion (and keeps every version before it).
settling=$(mktemp)
trap 'rm -f "$settling"' EXIT
(cd "$VAULT" && find . -type f -newermt "-$SETTLE seconds" -printf '/%P\n') > "$settling"
rsync -a --delete --exclude=/.git --exclude-from="$settling" "$VAULT/" "$HISTORY/"
[ -s "$settling" ] && echo "left for the next run, still being written: $(wc -l < "$settling") file(s)"

# 2. Commit what changed. The message says how many; the commit itself says which.
g add -A
if ! g diff --cached --quiet; then
  n=$(g diff --cached --name-only | wc -l)
  g -c user.name="vault history" -c user.email="vault@$(hostname)" \
    commit -q -m "vault $(date -u '+%Y-%m-%d %H:%M') UTC: $n file(s)" -m "$(g diff --cached --stat=120 | tail -n 30)"
  echo "committed $n file(s): $(g rev-parse --short HEAD)"
else
  echo "nothing changed"
fi

# 3. Push, unless the repository already has it. A failed push is tried again by the next run; the commits wait.
if [ "$(g rev-parse HEAD 2> /dev/null)" != "$(g ls-remote origin "refs/heads/$BRANCH" | cut -f1)" ]; then
  g push -q origin "HEAD:refs/heads/$BRANCH"
  echo "pushed"
fi
date -u +%Y%m%d-%H%M%S > "$HISTORY.ok.new" && chmod 644 "$HISTORY.ok.new" && mv "$HISTORY.ok.new" "$HISTORY.ok"
