# Playbook 1, tier 2. A second machine and a private network

For an agent. The chapter for people is [`chapters/01-servers.md`](../chapters/01-servers.md), section "Tier 2".
Follow the steps in order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `GAME` | The game host's public address | none: a person gives it |
| `CONTROL` | The control host's public address | none: a person gives it |
| `DEPLOY_USER` | The account made by playbook 1 on both machines | `nwn` |
| `GAME_WG` | The game host's private address | `10.77.0.2` |
| `CONTROL_WG` | The control host's private address | `10.77.0.1` |
| `WG_NET` | The size of the private network | `24` |

Secrets: each machine's private key is made on that machine and never leaves it. Never print
`/etc/wireguard/wg0.conf`. Public keys are not secret.

## Preconditions

Both machines have been through playbook 1, and neither has a private network yet:

```sh
for h in $GAME $CONTROL; do ssh $DEPLOY_USER@$h 'docker info --format "{{.LiveRestoreEnabled}}"; sudo test -e /etc/wireguard/wg0.conf && echo "has wg0" || echo "no wg0"'; done
```

Success: `true` and `no wg0`, twice. If either has `wg0` already, stop and ask.

The provider firewall of each machine allows UDP 51820 inbound from the other machine's address. A person does
that. Ask them to confirm it.

## Steps

### 1. Copy the script to both

```sh
for h in $GAME $CONTROL; do scp templates/host/wireguard.sh $DEPLOY_USER@$h:host/; done
```

Success: exit status 0.

### 2. Make the keys

```sh
CONTROL_KEY=$(ssh $DEPLOY_USER@$CONTROL "sudo ~/host/wireguard.sh init $CONTROL_WG/$WG_NET" | tail -1)
GAME_KEY=$(ssh $DEPLOY_USER@$GAME "sudo ~/host/wireguard.sh init $GAME_WG/$WG_NET" | tail -1)
echo ${#CONTROL_KEY} ${#GAME_KEY}
```

Success: `44 44`. These are the public keys.

### 3. Tell each about the other, and start

```sh
ssh $DEPLOY_USER@$CONTROL "sudo ~/host/wireguard.sh peer game $GAME_KEY $GAME_WG $GAME && sudo ~/host/wireguard.sh up"
ssh $DEPLOY_USER@$GAME "sudo ~/host/wireguard.sh peer control $CONTROL_KEY $CONTROL_WG $CONTROL && sudo ~/host/wireguard.sh up"
```

Success: each prints `added peer ...`, `listening on UDP port 51820` and `peers: 1`.

## Verify

```sh
ssh $DEPLOY_USER@$CONTROL "ping -c 3 -q $GAME_WG | tail -2"; ssh $DEPLOY_USER@$GAME "ping -c 3 -q $CONTROL_WG | tail -2"
```

Success: `0% packet loss` both ways.

```sh
for h in $GAME $CONTROL; do ssh $DEPLOY_USER@$h 'sudo wg show wg0 latest-handshakes | awk "{print systime()-\$2}"; systemctl is-enabled wg-quick@wg0; systemctl show docker -p After --value | grep -c wg-quick@wg0'; done
```

Success: for each machine a number under 180 (seconds since the handshake), `enabled`, `1`.

A private service is private. Publish a test container on the game host's private address, reach it from the
control host, fail to reach it from here, and remove it:

```sh
ssh $DEPLOY_USER@$GAME "docker run -d -q --name private-check -p $GAME_WG:8080:80 nginx:1.29-alpine >/dev/null && sleep 2"
ssh $DEPLOY_USER@$CONTROL "curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://$GAME_WG:8080/"
curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://$GAME:8080/ || true
ssh $DEPLOY_USER@$GAME 'docker rm -f private-check >/dev/null && docker image rm -f nginx:1.29-alpine >/dev/null; echo removed'
```

Success: `200`, then `000`, then `removed`.

## Roll back

```sh
for h in $GAME $CONTROL; do ssh $DEPLOY_USER@$h 'sudo systemctl disable --now wg-quick@wg0; sudo rm /etc/wireguard/wg0.conf /etc/systemd/system/docker.service.d/10-after-wireguard.conf; sudo systemctl daemon-reload; sudo ufw delete allow 51820/udp; sudo ufw delete allow in on wg0'; done
```

Success: no `wg0` on either machine (`ip link show wg0` fails), and `sudo ufw status` lists neither 51820 nor
`wg0`. Tested on one machine.

Do this only on machines where nothing is published on the private address yet. A container published there would
fail to start at the next boot.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- renting or deleting a machine, or changing a provider firewall;
- a machine that already has `/etc/wireguard/wg0.conf`;
- a private range that the person's machines already use for something else;
- no handshake after a minute: report `sudo wg show` without the keys, and the provider firewall rules as the
  person describes them;
- the roll back on a machine that has containers published on its private address.
