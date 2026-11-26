# Playbook 3, tier 3. Busy queues, and a proxy repaired at once

For an agent. The chapter for people is [`chapters/03-coolify.md`](../chapters/03-coolify.md), section "Tier 3".
Follow the steps in order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `CONTROL` | The control host's public address (where Coolify runs) | none: a person gives it |
| `MACHINES` | Every machine with Coolify's proxy and chapter 3's proxy check, by public address | `$CONTROL` |
| `DEPLOY_USER` | The deploy user | `nwn` |

Secrets:

- `COOLIFY_TOKEN` (Root), placed by a person as in playbook 3. Never print it, and never print a whole API response
  for an application: it contains secrets. The commands below print chosen fields only.
- `SKIP_TOKEN`, only for step 2: a token a person makes in the dashboard (**Keys & Tokens**, **API Tokens**, **New
  Token**, permissions **read** and **deploy** only) and puts in the environment of the shell you run in. It goes
  from there into a root-only file on the control host and is never printed.

## Preconditions

```sh
ssh -f -N -L 8000:localhost:8000 $DEPLOY_USER@$CONTROL 2>/dev/null
cl() { curl -s -X "$1" -H @<(printf 'Authorization: Bearer %s\n' "$COOLIFY_TOKEN") -H 'Content-Type: application/json' ${3:+-d "$3"} "http://localhost:8000/api/v1$2"; }
cl GET /version; echo
for m in $MACHINES; do ssh $DEPLOY_USER@$m 'hostname; systemctl is-active coolify-proxy-socket-check.timer; test -x /usr/local/sbin/coolify-proxy-socket-check && echo installed'; done
```

Success: `4.7.5`; for each machine its name, `active` and `installed`. If the check from playbook 3 is missing on a
machine, do that step of playbook 3 first.

## Steps

### 1. Coolify's own skip, on every application

```sh
for a in $(cl GET /applications | python3 -c 'import json,sys; [print(a["uuid"]) for a in json.load(sys.stdin)]'); do
  cl GET /applications/$a | python3 -c 'import json,sys; a=json.load(sys.stdin); s=a.get("settings") or a; print(a["name"], s.get("is_auto_cancel_queued_deployments_enabled"), s.get("is_auto_cancel_building_deployments_enabled"))'
done
```

Success: every line ends in `True False`. A line with `None` means this Coolify has no such setting: do step 2.
For a line with `False` first, tell the person which application, and switch it on only with their yes:

```sh
cl PATCH /applications/APP_UUID '{"is_auto_cancel_queued_deployments_enabled":true}' | python3 -c 'import json,sys; print("ok" if "uuid" in json.load(sys.stdin) else "FAILED")'
```

### 2. The helper (only if step 1 printed `None`)

```sh
[ -n "$SKIP_TOKEN" ] && echo "token present"
scp templates/coolify/skip-superseded.* $DEPLOY_USER@$CONTROL:
printf '%s\n' "$SKIP_TOKEN" | ssh $DEPLOY_USER@$CONTROL 'read -r t; printf "COOLIFY_URL=http://127.0.0.1:8000\nCOOLIFY_TOKEN='"'"'%s'"'"'\n" "$t" | sudo sh -c "umask 077; cat > /etc/coolify-skip-superseded.env" &&
  sudo install -m 755 skip-superseded.py /usr/local/sbin/coolify-skip-superseded &&
  sudo install -m 644 skip-superseded.service /etc/systemd/system/coolify-skip-superseded.service &&
  sudo install -m 644 skip-superseded.timer /etc/systemd/system/coolify-skip-superseded.timer &&
  sudo systemctl daemon-reload && sudo systemctl enable --now -q coolify-skip-superseded.timer && rm skip-superseded.* &&
  sudo sh -c "set -a; . /etc/coolify-skip-superseded.env; /usr/local/sbin/coolify-skip-superseded --dry-run"; echo "exit $?"'
```

Success: `token present`, then any `would cancel` lines and `exit 0`. `exit 2` means the token didn't arrive;
`exit 1` with `HTTP Error 401` or `403` means the token is wrong or lacks a permission: ask the person for a new one.

### 3. The proxy check from Docker's start, on each machine

```sh
for m in $MACHINES; do
  scp templates/coolify/proxy-socket-check.conf $DEPLOY_USER@$m:
  ssh $DEPLOY_USER@$m 'sudo install -D -m 644 proxy-socket-check.conf /etc/systemd/system/docker.service.d/50-coolify-proxy-socket.conf && sudo systemctl daemon-reload && rm proxy-socket-check.conf && systemctl show docker -p DropInPaths | grep -o 50-coolify-proxy-socket.conf'
done
```

Success: `50-coolify-proxy-socket.conf` once per machine. Nothing was restarted; it takes effect at Docker's next
start.

## Verify

```sh
ssh $DEPLOY_USER@$CONTROL 'systemctl is-active coolify-skip-superseded.timer 2>/dev/null || echo "no helper"; sudo journalctl -t coolify-skip-superseded --since -10min -p err --no-pager -q | wc -l'
```

Success: `active` and `0` (or `no helper` and `0` when step 2 was skipped).

The proxy repair is proved by stopping and starting Docker's socket, which restarts Docker. **Ask first**, and on a
game host only with the person's yes, because the game's container depends on Docker. With chapter 1's
`live-restore` the containers keep running. Then, on one machine:

```sh
ssh $DEPLOY_USER@$CONTROL 'sudo systemctl stop docker.service docker.socket && sudo systemctl start docker.socket docker.service; sleep 30; [ "$(stat -c %i /var/run/docker.sock)" = "$(docker exec coolify-proxy stat -c %i /var/run/docker.sock)" ] && echo "proxy socket matches"; sudo journalctl -t coolify-proxy-socket-check --since -2min -o cat --no-pager | tail -1'
```

Success: `proxy socket matches`, and `coolify-proxy holds an old Docker socket (...); restarting it`.

## Roll back

```sh
ssh $DEPLOY_USER@$CONTROL 'sudo systemctl disable --now -q coolify-skip-superseded.timer; sudo rm -f /etc/systemd/system/coolify-skip-superseded.service /etc/systemd/system/coolify-skip-superseded.timer /usr/local/sbin/coolify-skip-superseded /etc/coolify-skip-superseded.env; sudo systemctl daemon-reload'
for m in $MACHINES; do ssh $DEPLOY_USER@$m 'sudo rm -f /etc/systemd/system/docker.service.d/50-coolify-proxy-socket.conf && sudo systemctl daemon-reload'; done
```

Then tell the person to delete the helper's token in the dashboard. A setting switched on in step 1 is switched off
again with the same `PATCH` and `false`, with their yes.

## Stop and ask

- Before changing an application's setting in step 1.
- Before the socket test in Verify, and always before it on a game host.
- When the helper's token is refused (`401`, `403`): the person makes a new one.
- When the helper logs `couldn't cancel`: report the line; don't cancel deploys by hand.
- Never cancel a running deploy, or one started by hand or through the API.
