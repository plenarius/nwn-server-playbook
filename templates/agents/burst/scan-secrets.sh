#!/usr/bin/env bash
# scan-secrets.sh: before a server's disk is saved as an image, prove no secret is on it. Run as root on the
# server, last thing before chapter 1's prepare-snapshot.sh. Chapter 15, tier 3.
#
#   scan-secrets.sh [--tidy] NEEDLES
#
# NEEDLES is a file of secret values, one per line, kept in memory (under /run), never on the disk being
# scanned: every token, password and key body that was ever on this machine. Make it from the same files you
# pushed (for example: sed -n 's/^[A-Z_]*=//p' /run/agent/secrets.env > /run/burst/needles; cat
# /run/burst/token >> /run/burst/needles).
#   --tidy   first remove what usually holds secrets by accident: shell histories, git credential stores,
#            /tmp, and the logs (emptied: sudo writes every command line it runs to them).
# Then it searches every file on the root disk for every value, looks for token-shaped strings in /root,
# /etc, /var and /home, and checks that no git remote has a password in its address. It prints SCAN-CLEAN
# and exits 0 only if all three find nothing; otherwise it lists the files and exits 1. Save no image unless
# you saw SCAN-CLEAN.
set -euo pipefail
tidy=0; [ "${1:-}" = --tidy ] && { tidy=1; shift; }
needles=${1:?usage: scan-secrets.sh [--tidy] NEEDLES}
[ "$(id -u)" = 0 ] || { echo "run this as root" >&2; exit 1; }
case $(findmnt -no FSTYPE --target "$needles") in tmpfs|ramfs) ;; *) echo "$needles must be in memory (/run), not on the disk" >&2; exit 1 ;; esac
log() { echo "[scan $(date -u +%H:%M:%S)] $*"; }

if [ $tidy = 1 ]; then
  rm -f /root/.bash_history /home/*/.bash_history /root/.git-credentials /home/*/.git-credentials /root/.lesshst /home/*/.lesshst
  rm -rf /tmp/* /tmp/.[!.]* /var/tmp/* 2>/dev/null || true
  journalctl --rotate >/dev/null 2>&1; journalctl --vacuum-time=1s >/dev/null 2>&1 || true
  find /var/log -type f \( -name '*.gz' -o -name '*.[0-9]' \) -delete
  find /var/log -type f -exec truncate -s0 {} +   # sudo logs every command line, secrets included
  log "tidied: histories, credential stores, /tmp, logs"
fi

sed -i '/^[[:space:]]*$/d' "$needles"
n=$(grep -c '' "$needles")
[ "$n" -ge 1 ] || { echo "$needles holds no values" >&2; exit 1; }
awk 'length($0) < 8 { bad = 1 } END { exit bad }' "$needles" || { echo "a value in $needles is under 8 characters: too short to search for safely" >&2; exit 1; }
fail=0

files=$(find / -xdev -type f 2>/dev/null | wc -l)
hits=$(find / -xdev -type f -print0 2>/dev/null | xargs -0 -P "$(nproc)" -n 500 grep -lsaF -f "$needles" 2>/dev/null || true)
if [ -n "$hits" ]; then echo "SECRET FOUND in:"; echo "$hits"; fail=1
else log "searched $files files on / for $n secret value(s): none found"; fi

shaped=$(find /root /etc /var /home -xdev \( -path '/var/lib/docker' -o -path '/var/cache' -o -path '*/node_modules' -o -path '*/.cache' \) -prune \
  -o -type f -print0 2>/dev/null | xargs -0 grep -lsaE 'sk-ant-[a-z]{3}[0-9]{2}-|github_pat_[A-Za-z0-9_]{30,}|gh[pousr]_[A-Za-z0-9]{36}|-----BEGIN [A-Z ]*PRIVATE KEY-----' 2>/dev/null \
  | grep -vE '^/etc/ssh/ssh_host_' || true)
if [ -n "$shaped" ]; then echo "TOKEN-SHAPED STRING in:"; echo "$shaped"; fail=1
else log "no token-shaped strings or private keys in /root, /etc, /var, /home (host keys aside)"; fi

remotes=$(find /root /home -xdev -name config -path '*/.git/config' 2>/dev/null | xargs -r grep -lE 'url = https?://[^/@]+:[^/@]+@' || true)
if [ -n "$remotes" ]; then echo "GIT REMOTE WITH A PASSWORD in:"; echo "$remotes"; fail=1
else log "no git remote carries a password"; fi

[ $fail = 0 ] && echo SCAN-CLEAN
exit $fail
