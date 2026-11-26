#!/usr/bin/env bash
# Tells the watchdog how full the game host's disks are and when the newest backup was made. It lives in the game
# folder beside backup.sh, and the watchdog's SSH key can run this and nothing else. It reads; it changes nothing.
# Prints, for example:
#   disk 43 /
#   backup 20261126-090312
set -euo pipefail
cd "$(dirname "$0")"

# The disk the game folder is on, and the system's own disk if that is a different one.
df --output=pcent,target / . | tail -n +2 | sort -u -k2 | while read -r pct mount; do
  echo "disk ${pct%\%} $mount"
done

# backup.sh names each finished backup by its time in UTC; an unfinished one starts with a dot and doesn't count.
newest=$(ls -1 backups 2>/dev/null | grep -E '^[0-9]{8}-[0-9]{6}$' | sort | tail -n 1 || true)
echo "backup ${newest:-none}"
