#!/usr/bin/env bash
# push-secrets.sh: copy an agent's tokens from this hub into a worker's memory, never onto its disk.
#
#   push-secrets.sh SSH_TARGET [SECRETS_FILE] [AGENT_USER]
#
# SECRETS_FILE is KEY=value lines on this hub (default ~/.config/agent-secrets/worker.env, mode 600). It goes
# over SSH's standard input into /run/agent/secrets.env on the worker (a tmpfs, so it is gone at a reboot:
# push again then), owned by the agent user, mode 600. Nothing is printed but the names of the keys.
# SSH_TARGET is your admin account on the worker, which needs sudo there. Chapter 15, tier 3.
set -euo pipefail
target=${1:?usage: push-secrets.sh SSH_TARGET [SECRETS_FILE] [AGENT_USER]}
file=${2:-$HOME/.config/agent-secrets/worker.env}
user=${3:-agent}
[ "$(stat -c %a "$file")" = 600 ] || { echo "$file must be mode 600" >&2; exit 1; }
ssh -o BatchMode=yes "$target" "sudo install -d -m 700 -o $user -g $user /run/agent &&
  findmnt -no FSTYPE --target /run/agent | grep -qx tmpfs &&
  sudo install -m 600 -o $user -g $user /dev/stdin /run/agent/secrets.env &&
  sudo sed -n 's/=.*//p' /run/agent/secrets.env | tr '\n' ' '" < "$file"
echo "<- now in /run/agent/secrets.env on $target"
