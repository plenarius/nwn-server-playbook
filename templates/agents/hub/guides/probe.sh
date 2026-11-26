#!/usr/bin/env bash
# probe.sh: runs ON a worker, as the agent user, sent there by agent-docs-push. Prints what is really
# installed, as tab-separated rows the generator reads. agent-docs-push sets PROBE_TOOLS and PROBE_DATA
# (from agent-docs.env) ahead of this script. Chapter 15, tier 3.
: "${PROBE_TOOLS:?set by agent-docs-push}"
cd ~ || exit 1
# The PATH the agent server gives its agents, if a drop-in sets one; otherwise a usual one.
p=$(sed -n 's/^Environment=PATH=//p' ~/.config/systemd/user/*.service.d/*.conf 2>/dev/null | head -1 | sed "s|%h|$HOME|g")
export PATH=${p:-$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin}
for c in $PROBE_TOOLS; do
  command -v "$c" >/dev/null || { printf 'missing\t%s\n' "$c"; continue; }
  v=$(timeout 15 "$c" --version 2>&1 | grep -m1 -oE '[0-9]+\.[0-9]+(\.[0-9]+)?')
  printf 'tool\t%s\t%s\n' "$c" "${v:--}"
done
for d in $PROBE_DATA; do
  d=${d/#\~/$HOME}
  [ -r "$d" ] && [ -n "$(ls -A "$d" 2>/dev/null)" ] && printf 'data\t%s\n' "${d/#$HOME/\~}"
done
printf 'hw\t%s\t%s\n' "$(nproc)" "$(free -g | awk '/Mem:/{print $2}')"
systemctl show "user-$(id -u).slice" -p MemoryMax -p CPUQuotaPerSecUSec 2>/dev/null | sed 's/^/cap\t/'
printf 'tmp\t%s\n' "$(findmnt -no FSTYPE --target /tmp)"
