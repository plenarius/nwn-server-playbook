#!/usr/bin/env bash
# Tells the watchdog how full the game host's disks are and when the newest backup was made. It lives in the game
# folder beside backup.sh, and the watchdog's SSH key can run this and nothing else. It reads; it changes nothing.
# Prints, for example:
#   disk 43 /
#   backup 20261126-090312
#   borg 20261126-093514        (with chapter 12's tier 2: the last good borg backup)
#   vault 20261126-140102       (with chapter 12's tier 3: the last run of the vault's history that pushed)
set -euo pipefail
cd "$(dirname "$0")"

# The disk the game folder is on, and the system's own disk if that is a different one.
df --output=pcent,target / . | tail -n +2 | sort -u -k2 | while read -r pct mount; do
  echo "disk ${pct%\%} $mount"
done

# backup.sh names each finished backup by its time in UTC; an unfinished one starts with a dot and doesn't count.
newest=$(ls -1 backups 2>/dev/null | grep -E '^[0-9]{8}-[0-9]{6}$' | sort | tail -n 1 || true)
echo "backup ${newest:-none}"

# Chapter 12, tiers 2 and 3: the last good borg backup, and the vault history's last good run. The borg line
# appears once borg-backup.sh has made its first backup (it notes the time in /var/lib/nwn-borg; its own alert
# covers a backup that fails before then). The vault line appears once the history is set up; then "none" means it
# has never had a good run.
if [ -r /var/lib/nwn-borg/last-archive ]; then
  echo "borg $(cat /var/lib/nwn-borg/last-archive)"
fi
if [ -d vault-history ]; then
  echo "vault $(cat vault-history.ok 2>/dev/null || echo none)"
fi
