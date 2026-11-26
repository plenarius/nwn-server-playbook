#!/usr/bin/env bash
# prepare-host.sh: turn a fresh Ubuntu LTS cloud server into a host for a game server in Docker.
# Run as root, once. Safe to run again: every step checks before it changes anything.
#
#   DEPLOY_USER=nwn GAME_PORT=5121 ALLOW_WEB=1 SWAP_GB=2 ./prepare-host.sh
#
# Settings (environment variables):
#   DEPLOY_USER  the account you will log in as from now on (default: nwn)
#   GAME_PORT    the game's UDP port (default: 5121)
#   ALLOW_WEB    1 opens TCP 80 and 443 for a website on this machine (default: 0)
#   SWAP_GB      size of the swap file in GB, 0 for none (default: 2)
#   STEPS        the steps to run, in order (default: all of them)
#
# Steps: updates user ssh firewall docker swap clock cloudinit
# Run one step alone with e.g. STEPS=firewall ./prepare-host.sh
set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-nwn}"
GAME_PORT="${GAME_PORT:-5121}"
ALLOW_WEB="${ALLOW_WEB:-0}"
SWAP_GB="${SWAP_GB:-2}"
STEPS="${STEPS:-updates user ssh firewall docker swap clock cloudinit}"
HERE="$(cd "$(dirname "$0")" && pwd)"

[ "$(id -u)" = 0 ] || { echo "run this as root" >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive
say() { printf '\n== %s\n' "$*"; }

step_updates() {
  say "updates: install pending package updates"
  apt-get update -q
  apt-get -y -q dist-upgrade
  apt-get -y -q install ca-certificates curl ufw unattended-upgrades
  systemctl enable --now unattended-upgrades
}

step_user() {
  say "user: the account $DEPLOY_USER, with root's SSH keys"
  id "$DEPLOY_USER" >/dev/null 2>&1 || adduser --disabled-password --gecos "" "$DEPLOY_USER"
  usermod -aG sudo "$DEPLOY_USER"
  # No password is set on the account, so sudo cannot ask for one.
  echo "$DEPLOY_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-$DEPLOY_USER"
  chmod 440 "/etc/sudoers.d/90-$DEPLOY_USER"
  visudo -c -q
  home="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
  install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$home/.ssh"
  if [ ! -s "$home/.ssh/authorized_keys" ]; then
    [ -s /root/.ssh/authorized_keys ] || { echo "root has no SSH key to copy; add one first" >&2; exit 1; }
    install -m 600 -o "$DEPLOY_USER" -g "$DEPLOY_USER" /root/.ssh/authorized_keys "$home/.ssh/authorized_keys"
  fi
}

step_ssh() {
  say "ssh: keys only, no root login"
  home="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
  [ -s "$home/.ssh/authorized_keys" ] || { echo "$DEPLOY_USER has no SSH key; run the user step first" >&2; exit 1; }
  cat > /etc/ssh/sshd_config.d/10-keys-only.conf <<CONF
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
CONF
  sshd -t
  systemctl reload ssh
}

step_firewall() {
  say "firewall: deny incoming except SSH and the game (and the web ports with ALLOW_WEB=1)"
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 22/tcp comment SSH
  ufw allow "$GAME_PORT/udp" comment NWN
  if [ "$ALLOW_WEB" = 1 ]; then
    ufw allow 80/tcp comment HTTP
    ufw allow 443/tcp comment HTTPS
  fi
  ufw --force enable
}

step_docker() {
  say "docker: Docker Engine and Compose from Docker's own package repository"
  if ! command -v docker >/dev/null 2>&1; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -q
    apt-get -y -q install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi
  if ! cmp -s "$HERE/daemon.json" /etc/docker/daemon.json; then
    [ ! -f /etc/docker/daemon.json ] || cp -p /etc/docker/daemon.json "/etc/docker/daemon.json.before-$(date +%Y%m%d)"
    install -m 644 "$HERE/daemon.json" /etc/docker/daemon.json
    # A restart, not a reload: the log settings are only read at start. Nothing runs here yet.
    systemctl restart docker
  fi
  usermod -aG docker "$DEPLOY_USER"
}

step_swap() {
  [ "$SWAP_GB" != 0 ] || return 0
  say "swap: a ${SWAP_GB} GB swap file"
  if ! swapon --show | grep -q .; then
    fallocate -l "${SWAP_GB}G" /swapfile
    chmod 600 /swapfile
    mkswap -q /swapfile
    swapon /swapfile
    grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  fi
}

step_clock() {
  say "clock: UTC"
  timedatectl set-timezone Etc/UTC
}

step_cloudinit() {
  say "cloudinit: switch it off, keep the network file it wrote"
  ls /etc/netplan/*.yaml >/dev/null
  touch /etc/cloud/cloud-init.disabled
}

for s in $STEPS; do
  case "$s" in
    updates|user|ssh|firewall|docker|swap|clock|cloudinit) "step_$s" ;;
    *) echo "unknown step: $s" >&2; exit 1 ;;
  esac
done
say "done: $STEPS"
