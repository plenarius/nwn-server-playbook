#!/usr/bin/env bash
# A private network between your machines, with WireGuard. Run it as root on each machine.
#
#   wireguard.sh init ADDRESS                      e.g.  wireguard.sh init 10.77.0.1/24
#       Installs WireGuard, makes this machine's key (once) and prints its public key.
#       The private key never leaves the machine.
#   wireguard.sh peer NAME PUBLIC_KEY ADDRESS ENDPOINT
#                                                  e.g.  wireguard.sh peer game AbC...= 10.77.0.2 203.0.113.10
#       Adds another machine: its name (a label for you), the public key it printed, its private
#       address, and its public address. Adding the same key twice changes nothing.
#   wireguard.sh up
#       Starts the network, starts it at every boot, and lets traffic from the network through
#       this machine's firewall. Run it again after adding a peer.
#
# Settings: PORT (default 51820, UDP).
set -euo pipefail

PORT=${PORT:-51820}
CONF=/etc/wireguard/wg0.conf
[ "$(id -u)" = 0 ] || { echo "run this as root (sudo)" >&2; exit 1; }

case ${1:-} in
  init)
    address=${2:?give the private address with its network size, e.g. 10.77.0.1/24}
    command -v wg >/dev/null || { apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq wireguard-tools > /dev/null; }
    umask 077
    if [ ! -e "$CONF" ]; then
      key=$(wg genkey)
      printf '[Interface]\n# This machine\nAddress = %s\nListenPort = %s\nPrivateKey = %s\n' \
        "$address" "$PORT" "$key" > "$CONF"
    fi
    grep -q "^Address = $address\$" "$CONF" ||
      { echo "$CONF already exists with another address; not changing it" >&2; exit 1; }
    echo "public key of this machine:"
    sed -n 's/^PrivateKey = //p' "$CONF" | wg pubkey
    ;;
  peer)
    name=${2:?} pub=${3:?} addr=${4:?} endpoint=${5:?}
    [ -e "$CONF" ] || { echo "run init first" >&2; exit 1; }
    addr=${addr%/*}
    if grep -q "^PublicKey = $pub\$" "$CONF"; then
      echo "peer $name is already there"
    else
      printf '\n[Peer]\n# %s\nPublicKey = %s\nAllowedIPs = %s/32\nEndpoint = %s:%s\nPersistentKeepalive = 25\n' \
        "$name" "$pub" "$addr" "$endpoint" "$PORT" >> "$CONF"
      echo "added peer $name ($addr)"
    fi
    ;;
  up)
    [ -e "$CONF" ] || { echo "run init first" >&2; exit 1; }
    ufw allow "$PORT"/udp comment WireGuard > /dev/null
    ufw allow in on wg0 comment "private network" > /dev/null
    systemctl enable -q wg-quick@wg0
    if ip link show wg0 > /dev/null 2>&1; then
      wg syncconf wg0 <(wg-quick strip wg0)
    else
      systemctl start wg-quick@wg0
    fi
    # Containers published on this machine's private address must wait for it at boot.
    mkdir -p /etc/systemd/system/docker.service.d
    printf '[Unit]\nWants=wg-quick@wg0.service\nAfter=wg-quick@wg0.service\n' \
      > /etc/systemd/system/docker.service.d/10-after-wireguard.conf
    systemctl daemon-reload
    wg show wg0 | sed -n 's/^  listening port: /listening on UDP port /p'
    echo "peers: $(wg show wg0 peers | wc -l)"
    ;;
  *)
    sed -n '2,16p' "$0" >&2
    exit 2
    ;;
esac
