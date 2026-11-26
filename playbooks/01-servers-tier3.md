# Playbook 1, tier 3. Servers from a script, and a third site

For an agent. The chapter for people is [`chapters/01-servers.md`](../chapters/01-servers.md), section "Tier 3".
Follow the steps in order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer, unless a step says otherwise.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `HCLOUD_TOKEN_FILE` | The token of the provider project for short-lived servers, in a file (mode 600) | `~/.config/hcloud/playbook.token` |
| `SSH_KEYS` | The name of the person's SSH key in that project | none: a person gives it |
| `BUDGET_EUR` | The most all short-lived servers may cost together | `5`, or what the person says |
| `MAX_HOURS` | The longest life of one server | `6` |
| `CONTROL` | The control host's public address, where the reaper runs | none: a person gives it |
| `DEPLOY_USER` | The account made by playbook 1 on the machines | `nwn` |
| `THIRD` | The third site's public address, already through playbook 1 | none: a person gives it |
| `THIRD_WG` | The third site's private address | `10.77.0.3` |

Secrets: the token file is made by a person (chapter step 16). Never print it, never put it on a command line,
never copy it into a snapshot. It goes onto the control host only through step 4's `read` from standard input.

## Preconditions

```sh
export HCLOUD_TOKEN_FILE SSH_KEYS BUDGET_EUR MAX_HOURS
stat -c %a "$HCLOUD_TOKEN_FILE"
install -m 755 templates/provider/hcloud-servers.py ~/.local/bin/hcloud-servers
hcloud-servers price cx23 hel1 && hcloud-servers list | tail -1
```

Success: `600`, a line `EUR 0.0088 an hour` (or the current price), and `at most EUR ... in all; budget EUR ...`.
`Hetzner said: unable to authenticate`: stop and ask; do not retry with another token.

The person confirms the token belongs to a project that holds **no permanent machine**. Ask; you can't tell from
the token.

## Steps

### 1. Make a short-lived server

Only with the person's yes for this server, its type and its hours.

```sh
IP=$(hcloud-servers create NAME cx23 1 hel1) && echo "$IP"
```

Success: a line `created NAME (cx23, hel1, image ubuntu-26.04), expires HH:MM UTC, at most EUR 0.01` on standard
error and the address. `refused: ... over the budget`: stop and tell the person the numbers; never raise
`BUDGET_EUR` yourself. `Primary IP limit exceeded`: the project has no free address; ask.

### 2. Save it as a snapshot, and make a copy from it

Only on a server the person named for it, with no secret on its disk.

```sh
scp templates/provider/prepare-snapshot.sh $DEPLOY_USER@$IP:host/
ssh $DEPLOY_USER@$IP 'sudo ~/host/prepare-snapshot.sh before'
IMAGE=$(hcloud-servers snapshot NAME "what it holds, date")
ssh $DEPLOY_USER@$IP 'sudo ~/host/prepare-snapshot.sh after'
```

Success: `ready to snapshot: ...`, a number, then `put back: machine id ..., cloud-init off`. If `after` was not run,
run it before anything else: the original would make new host keys at its next boot.

A copy, with the person's yes:

```sh
COPY=$(hcloud-servers create NAME-2 cx23 1 hel1 $IMAGE)
ssh $DEPLOY_USER@$COPY 'sudo ~/host/prepare-snapshot.sh after; cat /etc/machine-id'
```

Success: `a new server from the snapshot: keeps its own machine id ...`, and an id that differs from the
original's. The copy's host key is new: remove the old entry for that address from `known_hosts` if the person's
SSH client complains about a reused address, never for a machine that existed before.

### 3. Delete what you made

```sh
hcloud-servers delete NAME-2 && hcloud-servers delete NAME && hcloud-servers delete-image $IMAGE
hcloud-servers list | tail -1; hcloud-servers images
```

Success: `deleted ...` three times; `at most EUR 0.00 in all` if nothing else is running; no line for `$IMAGE`.

### 4. The reaper on the control host

```sh
scp templates/provider/hcloud-servers.py templates/provider/hcloud-reaper.* templates/provider/reaper.env.example $DEPLOY_USER@$CONTROL:
ssh $DEPLOY_USER@$CONTROL 'sudo install -m 755 hcloud-servers.py /usr/local/bin/hcloud-servers && sudo install -d -m 700 /etc/hcloud-reaper && sudo install -m 600 reaper.env.example /etc/hcloud-reaper/reaper.env && sudo install -m 644 hcloud-reaper.service hcloud-reaper.timer /etc/systemd/system/ && sudo systemctl daemon-reload && echo installed'
ssh $DEPLOY_USER@$CONTROL 'read -rs t; printf "%s\n" "$t" | sudo install -m 600 /dev/stdin /etc/hcloud-reaper/token && echo saved' < "$HCLOUD_TOKEN_FILE"
ssh $DEPLOY_USER@$CONTROL 'sudo systemctl start hcloud-reaper.service; sudo journalctl -u hcloud-reaper -n 3 --no-pager -o cat | head -1; sudo systemctl enable -q --now hcloud-reaper.timer; systemctl is-active hcloud-reaper.timer'
```

Success: `installed`, `saved`, `nothing to reap` (or `deleted ...` lines: report them to the person at once), then
`active`.

### 5. The third site joins the private network

`THIRD` has been through playbook 1, and through playbook 1 tier 2's step 1 (the script is in `~/host`). The
person has opened UDP 51820 at each provider's firewall for the others' addresses.

```sh
THIRD_KEY=$(ssh $DEPLOY_USER@$THIRD "sudo ~/host/wireguard.sh init $THIRD_WG/24" | tail -1); echo ${#THIRD_KEY}
ssh $DEPLOY_USER@$THIRD "sudo ~/host/wireguard.sh peer control $CONTROL_KEY 10.77.0.1 $CONTROL && sudo ~/host/wireguard.sh peer game $GAME_KEY 10.77.0.2 $GAME && sudo ~/host/wireguard.sh up"
for h in $CONTROL $GAME; do ssh $DEPLOY_USER@$h "sudo ~/host/wireguard.sh peer third $THIRD_KEY $THIRD_WG $THIRD && sudo ~/host/wireguard.sh up"; done
```

`CONTROL_KEY` and `GAME_KEY` are the public keys from playbook 1 tier 2 (`sudo wg show wg0 public-key` on each).
Success: `44`, then `peers: 2` on the third, and `peers: 2` on each of the other two.

## Verify

```sh
for h in $CONTROL $GAME; do ssh $DEPLOY_USER@$h "ping -c 3 -q $THIRD_WG | tail -2"; done
ssh $DEPLOY_USER@$CONTROL 'systemctl list-timers hcloud-reaper.timer --no-pager | grep -c hcloud-reaper'
hcloud-servers reap --dry-run
```

Success: `0% packet loss` twice (expect tens of milliseconds to another provider), `1`, and `nothing to reap`.

## Roll back

- The reaper: `ssh $DEPLOY_USER@$CONTROL 'sudo systemctl disable --now hcloud-reaper.timer; sudo rm -r /etc/hcloud-reaper /etc/systemd/system/hcloud-reaper.* /usr/local/bin/hcloud-servers; sudo systemctl daemon-reload'`.
  Success: `systemctl status hcloud-reaper.timer` says it could not be found.
- The third peer: on the third, playbook 1 tier 2's roll back; on the other two, delete its `[Peer]` block from
  `/etc/wireguard/wg0.conf` (the block whose comment is `# third`) and run `sudo ~/host/wireguard.sh up`. Success:
  `peers: 1` on each.
- Servers and snapshots: step 3.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- making the project, its token, or any server not covered by a yes with its type and hours;
- a refusal from the cost guard, or a wish to raise `BUDGET_EUR` or `MAX_HOURS`;
- deleting or reaping anything you didn't make in this session, or switching protection off;
- **any rescale, disk growth or type change of an existing machine**: it may be on a legacy price (chapter step 22);
- a snapshot of a machine that may hold secrets;
- `reap` deleting a server you didn't expect;
- no handshake with the third site after a minute: report `sudo wg show` without the keys.
