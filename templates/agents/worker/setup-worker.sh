#!/usr/bin/env bash
# setup-worker.sh: make this machine an agent worker. Run as root from the folder that holds it and its
# neighbours (templates/agents/worker). Safe to run again: each step writes the same files.
#
#   ./setup-worker.sh                 every step, with the settings in worker.env (or worker.env.example)
#   STEPS="limits cleaner" ./setup-worker.sh
#
# Steps:
#   user     the agent account: no sudo, not in docker, lingering so its services run without a login
#   limits   a fence for everything it runs (user-<uid>.slice) and MemoryLow on its parents
#   secrets  /run/agent, a folder in memory for its tokens, made again at each boot
#   cleaner  the hourly scratch cleaner
#   git      the credential helper, its token map and a .gitconfig that uses it
#   server   a drop-in for the agent server's user unit: the tokens, PATH and MemoryLow
# Chapter 15, tier 3.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SETTINGS=${SETTINGS:-$HERE/worker.env}
[ -f "$SETTINGS" ] || SETTINGS=$HERE/worker.env.example
. "$SETTINGS"
STEPS=${STEPS:-user limits secrets cleaner git server}
[ "$(id -u)" = 0 ] || { echo "run this as root" >&2; exit 1; }
say() { printf '== %s\n' "$*"; }

step_user() {
  say "user: $AGENT_USER"
  id "$AGENT_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$AGENT_USER"
  for g in sudo admin wheel docker; do gpasswd -d "$AGENT_USER" "$g" >/dev/null 2>&1 || true; done
  passwd -l "$AGENT_USER" >/dev/null
  loginctl enable-linger "$AGENT_USER"
  if sudo -l -U "$AGENT_USER" 2>/dev/null | grep -q 'may run'; then
    echo "WARNING: $AGENT_USER can still use sudo; check /etc/sudoers.d" >&2; exit 1
  fi
  echo "$AGENT_USER: uid $(id -u "$AGENT_USER"), no sudo, linger on"
}

step_limits() {
  local uid; uid=$(id -u "$AGENT_USER")
  say "limits: user-$uid.slice and MemoryLow"
  install -d "/etc/systemd/system/user-$uid.slice.d" "/etc/systemd/system/user@$uid.service.d"
  cat > "/etc/systemd/system/user-$uid.slice.d/50-agent-limits.conf" <<EOF
# Everything $AGENT_USER runs: never starve the services on this host. Written by setup-worker.sh.
[Slice]
MemoryHigh=$MEM_HIGH
MemoryMax=$MEM_MAX
MemorySwapMax=$MEM_SWAP_MAX
MemoryLow=$PARENT_MEMORY_LOW
CPUQuota=$CPU_QUOTA
CPUWeight=50
IOWeight=50
TasksMax=$TASKS_MAX
EOF
  # MemoryLow only protects a unit if every parent above it grants at least as much: user.slice, the slice
  # above (with MemoryLow), user@<uid>.service here, and app.slice inside the user manager (step server).
  install -d /etc/systemd/system/user.slice.d
  printf '# Written by setup-worker.sh: see user-%s.slice.d.\n[Slice]\nMemoryLow=%s\n' "$uid" "$PARENT_MEMORY_LOW" \
    > /etc/systemd/system/user.slice.d/50-agent-memory-low.conf
  cat > "/etc/systemd/system/user@$uid.service.d/50-memory-low.conf" <<EOF
# Keeps memory for $AGENT_USER's own services (the agent server) under pressure. Written by setup-worker.sh.
[Service]
MemoryLow=$PARENT_MEMORY_LOW
EOF
  systemctl daemon-reload
  systemctl show "user-$uid.slice" -p MemoryHigh -p MemoryMax -p MemorySwapMax -p MemoryLow -p CPUQuotaPerSecUSec -p TasksMax | tr '\n' ' '; echo
}

step_secrets() {
  say "secrets: /run/agent (memory only)"
  printf 'd /run/agent 0700 %s %s -\n' "$AGENT_USER" "$AGENT_USER" > /etc/tmpfiles.d/agent-secrets.conf
  systemd-tmpfiles --create /etc/tmpfiles.d/agent-secrets.conf
  stat -c '%n %U %a' /run/agent; findmnt -no FSTYPE --target /run/agent
}

step_cleaner() {
  say "cleaner: agent-tmp-clean, hourly"
  install -m 755 "$HERE/agent-tmp-clean" /usr/local/sbin/agent-tmp-clean
  install -d /etc/agent
  { echo "AGENT_USER=$AGENT_USER"; echo "SCRATCH=$SCRATCH"; echo "KEEP_MIN=$KEEP_MIN"; } > /etc/agent/tmp-clean.env
  install -m 644 "$HERE/agent-tmp-clean.service" "$HERE/agent-tmp-clean.timer" /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable -q --now agent-tmp-clean.timer
  systemctl is-active agent-tmp-clean.timer
}

step_git() {
  local home; home=$(getent passwd "$AGENT_USER" | cut -d: -f6)
  say "git: credential helper for $AGENT_USER"
  install -d -o "$AGENT_USER" -g "$AGENT_USER" "$home/.local" "$home/.local/bin" "$home/.config" "$home/.config/agent"
  install -m 755 -o "$AGENT_USER" -g "$AGENT_USER" "$HERE/git-credential-agent" "$home/.local/bin/"
  [ -e "$home/.config/agent/tokens.map" ] ||
    install -m 644 -o "$AGENT_USER" -g "$AGENT_USER" "$HERE/tokens.map.example" "$home/.config/agent/tokens.map"
  cd "$home"   # git checks the folder it runs in, and the agent can't read root's
  sudo -u "$AGENT_USER" git config --global credential.helper "$home/.local/bin/git-credential-agent"
  sudo -u "$AGENT_USER" git config --global credential.useHttpPath true
  sudo -u "$AGENT_USER" git config --global init.defaultBranch main
  sudo -u "$AGENT_USER" git config --global --get credential.helper
}

step_server() {
  local home; home=$(getent passwd "$AGENT_USER" | cut -d: -f6)
  say "server: drop-in for $AGENT_SERVICE"
  local d="$home/.config/systemd/user/$AGENT_SERVICE.d"
  install -d -o "$AGENT_USER" -g "$AGENT_USER" "$home/.config" "$home/.config/systemd" "$home/.config/systemd/user" "$d"
  cat > "$d/10-agent.conf" <<EOF
# Written by setup-worker.sh. The tokens come from memory (/run/agent), never from a file on disk.
[Service]
EnvironmentFile=-/run/agent/secrets.env
Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin
MemoryLow=$SERVER_MEMORY_LOW
EOF
  # The user's app.slice is the server's parent inside the user manager: it needs MemoryLow too.
  install -d -o "$AGENT_USER" -g "$AGENT_USER" "$home/.config/systemd/user/app.slice.d"
  printf '[Slice]\nMemoryLow=%s\n' "$PARENT_MEMORY_LOW" > "$home/.config/systemd/user/app.slice.d/50-memory-low.conf"
  chown -R "$AGENT_USER:" "$home/.config/systemd"
  echo "$d/10-agent.conf"
}

for s in $STEPS; do "step_$s"; done
