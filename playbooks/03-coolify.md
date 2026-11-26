# Playbook 3. Coolify (tier 2)

For an agent. The chapter for people is [`chapters/03-coolify.md`](../chapters/03-coolify.md). Follow the steps in
order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `CONTROL` | The control host's public address | none: a person gives it |
| `GAME` | The game host's public address | none: a person gives it |
| `GAME_WG` | The game host's private address | `10.77.0.2` |
| `DEPLOY_USER` | The deploy user on both machines | `nwn` |
| `REPO` | A GitHub repository with a `Dockerfile`, as `owner/name`, for the deploy-on-merge check | none: a person gives it |
| `BASE_DIR` | The folder in `REPO` that holds the `Dockerfile` | `/` |

Secrets: `COOLIFY_TOKEN`, an API token a person makes in the dashboard (**Keys & Tokens**, **API Tokens**, **New
Token**, permission **Root**; it expires after 30 days unless they choose otherwise) and puts in the environment of
the shell you run in. Never print it. Never print a
whole API response for an application, a service, a key or a storage: they contain secrets. Every command below
prints chosen fields only.

## Before you start: what a person does

These need a person, because they involve a password, money or a provider's console:

1. Chapter 1, both tiers, on both machines.
2. The control host's provider firewall allows TCP 22 and UDP 51820 from the game host, and nothing on 8000, 6001
   or 6002.
3. Chapter 3, steps 2 and 3: Coolify installed with the admin account, and the dashboard opened once (**Skip
   setup**).
4. **Settings**, **Advanced**, **API access** set to **Enabled**. It's off after a new install.
5. The API token, as above.

## Preconditions

```sh
ssh -f -N -L 8000:localhost:8000 $DEPLOY_USER@$CONTROL
cl() { curl -s -X "$1" -H @<(printf 'Authorization: Bearer %s\n' "$COOLIFY_TOKEN") -H 'Content-Type: application/json' ${3:+-d "$3"} "http://localhost:8000/api/v1$2"; }
cl GET /version; echo
cl GET /servers | python3 -c 'import json,sys; [print(s["name"], s["user"]) for s in json.load(sys.stdin)]'
```

Success: `4.7.5`, then one line `localhost root`. Define `cl` the same way in every later shell.

## Steps

### 1. Coolify's own machine, as the deploy user

```sh
ssh $DEPLOY_USER@$CONTROL 'sudo grep coolify /root/.ssh/authorized_keys >> ~/.ssh/authorized_keys; grep -c coolify ~/.ssh/authorized_keys'
LOCAL=$(cl GET /servers | python3 -c 'import json,sys; print([s["uuid"] for s in json.load(sys.stdin) if s["name"]=="localhost"][0])')
cl PATCH /servers/$LOCAL "{\"user\":\"$DEPLOY_USER\"}" > /dev/null; cl POST /servers/$LOCAL/validate > /dev/null; sleep 40
cl GET /servers/$LOCAL | python3 -c 'import json,sys; s=json.load(sys.stdin); print(s["user"], s["settings"]["is_usable"])'
```

Success: `1`, then `nwn True`.

### 2. The game host, by its private address

```sh
ssh $DEPLOY_USER@$GAME 'sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq jq > /dev/null 2>&1; command -v jq'
ssh $DEPLOY_USER@$CONTROL 'sudo grep coolify /root/.ssh/authorized_keys' | ssh $DEPLOY_USER@$GAME 'cat >> ~/.ssh/authorized_keys; grep -c coolify ~/.ssh/authorized_keys'
KEY=$(cl GET /security/keys | python3 -c 'import json,sys; print([k["uuid"] for k in json.load(sys.stdin) if k["name"]=="localhost'"'"'s key"][0])')
GAMESRV=$(cl POST /servers "{\"name\":\"game\",\"ip\":\"$GAME_WG\",\"port\":22,\"user\":\"$DEPLOY_USER\",\"private_key_uuid\":\"$KEY\",\"instant_validate\":true}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["uuid"])'); sleep 60
cl GET /servers/$GAMESRV | python3 -c 'import json,sys; s=json.load(sys.stdin); print(s["ip"], s["user"], s["settings"]["is_usable"])'
```

Success: `/usr/bin/jq`, `1`, then `10.77.0.2 nwn True`.

### 3. Unused volumes are kept

```sh
cl GET /servers | python3 -c 'import json,sys; [print(s["name"], s["settings"]["delete_unused_volumes"]) for s in json.load(sys.stdin)]'
```

Success: both lines end in `False`. If one says `True`, stop and ask: a person changes it on that server's
**Docker Cleanup** page.

### 4. The proxy check, on both machines

```sh
for h in $CONTROL $GAME; do scp templates/coolify/proxy-socket-check.* $DEPLOY_USER@$h: && ssh $DEPLOY_USER@$h 'sudo install -m 755 proxy-socket-check.sh /usr/local/sbin/coolify-proxy-socket-check && sudo install -m 644 proxy-socket-check.service /etc/systemd/system/coolify-proxy-socket-check.service && sudo install -m 644 proxy-socket-check.timer /etc/systemd/system/coolify-proxy-socket-check.timer && sudo systemctl daemon-reload && sudo systemctl enable --now -q coolify-proxy-socket-check.timer && systemctl is-active coolify-proxy-socket-check.timer && rm proxy-socket-check.*'; done
```

Success: `active`, twice.

If the game host also runs the web server from chapter 7 or 11, Coolify's proxy can't have ports 80 and 443 there.
Stopping it has no API: stop and ask a person to stop it on that server's **Proxy** page.

### 5. The deploy-on-merge check

**Ask first.** Tell the person you will add a read-only deploy key and a webhook to `REPO`, and an application in
Coolify reachable only from the control host. Wait for a yes.

```sh
umask 077; T=$(mktemp -d); ssh-keygen -q -t ed25519 -N '' -C coolify-deploy -f $T/key
gh api repos/$REPO/keys -f title=coolify -f key="$(cat $T/key.pub)" -F read_only=true -q .read_only
DK=$(python3 -c 'import json,sys; print(json.dumps({"name":"github-deploy","private_key":open(sys.argv[1]).read()}))' $T/key | cl POST /security/keys "$(cat)" | python3 -c 'import json,sys; print(json.load(sys.stdin)["uuid"])'); rm -r $T
PROJ=$(cl POST /projects '{"name":"deploy-check"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["uuid"])')
APP=$(cl POST /applications/private-deploy-key "{\"project_uuid\":\"$PROJ\",\"server_uuid\":\"$LOCAL\",\"environment_name\":\"production\",\"private_key_uuid\":\"$DK\",\"git_repository\":\"git@github.com:$REPO.git\",\"git_branch\":\"main\",\"build_pack\":\"dockerfile\",\"base_directory\":\"$BASE_DIR\",\"ports_exposes\":\"80\",\"ports_mappings\":\"127.0.0.1:8081:80\",\"name\":\"deploy-check\",\"instant_deploy\":true}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["uuid"])')
SECRET=$(openssl rand -hex 20); cl PATCH /applications/$APP "{\"manual_webhook_secret_github\":\"$SECRET\"}" > /dev/null
gh api repos/$REPO/hooks -f name=web -F active=true -f 'events[]=push' -f "config[url]=http://$CONTROL:8000/webhooks/source/github/events/manual" -f config[content_type]=json -f "config[secret]=$SECRET" -q .active; unset SECRET
```

Success: `true`, then `true`. The webhook only reaches Coolify once the person has opened TCP 8000 at the control
host's provider firewall to GitHub's webhook senders (`gh api meta -q '.hooks[]'`) and to the game host's address.
Ask them to confirm it.

## Verify

```sh
sleep 60; ssh $DEPLOY_USER@$CONTROL 'curl -s -m 5 -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8081/'
HOOK=$(gh api repos/$REPO/hooks -q '[.[] | select(.config.url | endswith("/events/manual"))][0].id'); gh api repos/$REPO/hooks/$HOOK/deliveries -q '.[0] | "\(.event) \(.status_code)"'
cl GET /servers | python3 -c 'import json,sys; [print(s["name"], s["settings"]["is_reachable"], s["settings"]["is_usable"]) for s in json.load(sys.stdin)]'
for p in 8000 6001 6002; do timeout 4 bash -c "</dev/tcp/$CONTROL/$p" 2>/dev/null && echo "open $p"; done
```

Success: `200`; `ping 200` (or `push 200`); both servers `True True`; no `open` lines from this computer (unless the
person's own address is among the allowed senders).

The last check is the person's: they merge a small change in `REPO` and see it in
`curl -s http://127.0.0.1:8081/` on the control host within half a minute.

## Roll back

- **The deploy-on-merge check:** `cl DELETE /applications/$APP`, then delete the webhook and the deploy key on
  GitHub (`gh api -X DELETE repos/$REPO/hooks/$HOOK`, and the key under the repository's **Deploy keys**).
- **The game host:** `cl DELETE /servers/$GAMESRV`, only while it has no resources in Coolify.
- **The proxy check:** `sudo systemctl disable --now coolify-proxy-socket-check.timer` on each machine.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- installing or removing Coolify, or anything that needs the admin password;
- changing a provider firewall, or anything in GitHub other than the deploy key and webhook of step 5;
- step 5 without a yes;
- stopping or switching a proxy (it has no API, and it can take websites down);
- deleting a server, an application or a service that someone else made;
- turning on deletion of unused volumes, ever;
- a server that stays unusable after validation: report the first lines of its validation output, not the whole
  response.
