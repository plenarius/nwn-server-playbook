# Playbook 10, tier 2. The Discord bot

For an agent. The chapter for people is [`chapters/10-discord-bot.md`](../chapters/10-discord-bot.md), section
"Tier 2". Follow the steps in order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer, with `gh` signed in as someone who
may change the bot's repository and the content repositories' settings.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `CONTROL` | The control host's public address | none: a person gives it |
| `DEPLOY_USER` | The deploy user on the control host | `nwn` |
| `BOT_REPO` | The bot's private GitHub repository, as `owner/name`, holding `templates/bot` at its root (chapter step 4) | none: a person gives it |
| `BOT_HOST` | The name GitHub calls the bot on, such as `bot.example.org` | none: a person gives it |
| `BOT_ENV` | The bot's settings file on this computer, filled in from `templates/bot/.env.example`, mode 600 | none: a person places it |
| `CONTENT_REPOS` | The repositories whose merges go to the changelog, as `owner/name`, space separated | none: a person gives them |

Secrets: `COOLIFY_TOKEN` (Root), placed by a person as in playbook 3. The Discord token, the API key and the webhook
secret are in `BOT_ENV`, which a person fills in: never print it, never print a line of it, and never print an API
response for the application or its variables. The deploy key's private half goes from a private temporary file
straight into Coolify and is then deleted.

## Preconditions

```sh
ssh -f -N -L 8000:localhost:8000 $DEPLOY_USER@$CONTROL 2>/dev/null
cl() { curl -s -X "$1" -H @<(printf 'Authorization: Bearer %s\n' "$COOLIFY_TOKEN") -H 'Content-Type: application/json' ${3:+-d "$3"} "http://localhost:8000/api/v1$2"; }
LOCALSRV=$(cl GET /servers | python3 -c 'import json,sys; print([s["uuid"] for s in json.load(sys.stdin) if not s["ip"].startswith("10.")][0])'); echo $LOCALSRV
gh repo view $BOT_REPO --json visibility -q .visibility
gh api repos/$BOT_REPO/contents/Dockerfile -q .name
stat -c %a $BOT_ENV
python3 -c '
import sys
s = dict(l.rstrip("\n").split("=", 1) for l in open(sys.argv[1]) if "=" in l and not l.lstrip().startswith("#"))
need = ["DISCORD_TOKEN", "GUILD_ID", "DASHBOARD_CHANNEL_ID", "CHANGELOG_CHANNEL_ID", "STAFF_ROLE_ID", "OPS_API_URL", "OPS_API_KEY", "GITHUB_WEBHOOK_SECRET"]
print("missing:", [k for k in need if not s.get(k)] or "none")' $BOT_ENV
ssh $DEPLOY_USER@$CONTROL 'docker run --rm --network coolify python:3.12-slim python -c "import urllib.request; print(urllib.request.urlopen(\"http://10.77.0.1:8100/health\", timeout=5).read().decode())"'
cl GET /applications | python3 -c 'import json,sys; print(sum(1 for a in json.load(sys.stdin) if a["name"]=="bot"), "applications named bot")'
```

Success: an id; `PRIVATE`; `Dockerfile`; `600`; `missing: none`; `{"status":"ok"}` (the operations API, reached the
way the bot will reach it); `0 applications named bot`. Anything else: stop and ask. Ask the person, too, whether
the key in `OPS_API_KEY` is the API's **team** key; never put the admin or full key in the bot.

## Steps

### 1. A deploy key

**Ask first**: this adds a read-only deploy key to `BOT_REPO`. After the yes:

```sh
umask 077; T=$(mktemp -d)
ssh-keygen -q -t ed25519 -N '' -C coolify-bot -f $T/key
gh api repos/$BOT_REPO/keys -f title=coolify-bot -f key="$(cat $T/key.pub)" -F read_only=true -q .read_only
KEY=$(python3 -c 'import json,sys; print(json.dumps({"name":"bot-deploy","private_key":open(sys.argv[1]).read()}))' $T/key | cl POST /security/keys "$(cat)" | python3 -c 'import json,sys; print(json.load(sys.stdin)["uuid"])'); rm -r $T; echo $KEY
```

Success: `true`, then an id.

### 2. The application, its volume and its settings, not deployed

```sh
PROJ=$(cl POST /projects '{"name":"bot"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["uuid"])')
APP=$(cl POST /applications/private-deploy-key "{\"project_uuid\":\"$PROJ\",\"server_uuid\":\"$LOCALSRV\",\"environment_name\":\"production\",\"private_key_uuid\":\"$KEY\",\"git_repository\":\"git@github.com:$BOT_REPO.git\",\"git_branch\":\"main\",\"build_pack\":\"dockerfile\",\"base_directory\":\"/\",\"ports_exposes\":\"9090\",\"domains\":\"https://$BOT_HOST\",\"name\":\"bot\",\"instant_deploy\":false}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("uuid") or "FAILED")'); echo $APP
cl POST /applications/$APP/storages '{"type":"persistent","name":"bot-data","mount_path":"/data"}' | python3 -c 'import json,sys; print(json.load(sys.stdin).get("mount_path") or "FAILED")'
python3 -c '
import json, sys
data = []
for line in open(sys.argv[1]):
    line = line.rstrip("\n")
    if not line or line.lstrip().startswith("#") or "=" not in line: continue
    key, value = line.split("=", 1)
    data.append({"key": key, "value": value})
print(json.dumps({"data": data}))' $BOT_ENV | cl PATCH /applications/$APP/envs/bulk "$(cat)" | python3 -c 'import json,sys; print("copied" if isinstance(json.load(sys.stdin), list) else "FAILED")'
```

Success: an id, `/data`, `copied`.

**Ask the person** to open TCP 80 and 443 to everyone at the control host's provider firewall, if they aren't open
already (chapter 11 tier 2 opens them). Wait for their yes.

### 3. Move the name, then deploy

**Ask first.** `BOT_HOST` is made for `CONTROL`, which costs one certificate. The person makes the record, or you do
with playbook 2 after their yes. Check at the source:

```sh
NS=$(dig +short NS ${BOT_HOST#*.} | head -1); dig +short $BOT_HOST @$NS | tail -1
```

Success: `CONTROL`. Only then:

```sh
APP=$(cl GET /applications | python3 -c 'import json,sys; r=[a["uuid"] for a in json.load(sys.stdin) if a["name"]=="bot"]; print(r[0] if len(r)==1 else "")'); echo "application: ${APP:-none or several}"
cl POST "/deploy?uuid=$APP&force=false" > /dev/null
for i in $(seq 40); do st=$(cl GET "/deployments/applications/$APP?take=1" | python3 -c 'import json,sys; d=json.load(sys.stdin); d=d.get("deployments",d) if isinstance(d,dict) else d; print(d[0]["status"] if d else "none")'); [ "$st" = finished ] || [ "$st" = failed ] && break; sleep 6; done; echo "deploy: $st"
ssh $DEPLOY_USER@$CONTROL "docker logs \$(docker ps -q --filter name=$APP | head -1) 2>&1 | grep -E 'commands synced|SYNC_COMMANDS|webhook receiver|dashboard posted|Discord refused|Missing settings'"
curl -s -m 10 https://$BOT_HOST/health
```

Success: one id; `deploy: finished`; `commands synced to the guild: restart, cancel-restart`, `webhook receiver on
port 9090` and `dashboard posted: message ...` (or no `dashboard posted` line when the bot found its earlier message);
`{"ok": true, ...}`. `deploy: failed` with `Discord refused the token` or `Missing settings`: the person fixes
`BOT_ENV`; send it again with step 2's last command, and deploy again. If the deploy finished but `/health` has no
certificate after two minutes, run `docker restart coolify-proxy` on the control host once and check again.

### 4. Deploy on merge

**Ask first**: this adds a webhook to `BOT_REPO`, pointing at `CONTROL` on port 8000. After the yes:

```sh
SECRET=$(openssl rand -hex 20)
cl PATCH /applications/$APP "{\"manual_webhook_secret_github\":\"$SECRET\"}" | python3 -c 'import json,sys; print("secret set" if "uuid" in json.load(sys.stdin) else "FAILED")'
HOOK=$(gh api repos/$BOT_REPO/hooks -f name=web -F active=true -f 'events[]=push' -f "config[url]=http://$CONTROL:8000/webhooks/source/github/events/manual" -f config[content_type]=json -f "config[secret]=$SECRET" -q .id); unset SECRET
sleep 10; gh api repos/$BOT_REPO/hooks/$HOOK/deliveries -q '.[0] | "\(.event) \(.status_code)"'
```

Success: `secret set`, then `ping 200`.

### 5. The changelog webhooks

**Ask first**: this adds one webhook to each of `CONTENT_REPOS`. After the yes:

```sh
for R in $CONTENT_REPOS; do
  python3 -c '
import json, sys
s = dict(l.rstrip("\n").split("=", 1) for l in open(sys.argv[1]) if "=" in l and not l.lstrip().startswith("#"))
print(json.dumps({"name": "web", "active": True, "events": ["pull_request"],
                  "config": {"url": sys.argv[2], "content_type": "json", "secret": s["GITHUB_WEBHOOK_SECRET"], "insecure_ssl": "0"}}))' \
    $BOT_ENV "https://$BOT_HOST/github" | gh api -X POST repos/$R/hooks --input - -q .id > /tmp/hook-$$.id
  sleep 5; echo "$R $(gh api repos/$R/hooks/$(cat /tmp/hook-$$.id)/deliveries -q '.[0] | "\(.event) \(.status_code)"')"; rm -f /tmp/hook-$$.id
done
```

Success: `<repo> ping 200` for each.

## Verify

```sh
ssh $DEPLOY_USER@$CONTROL "docker inspect -f '{{.State.Health.Status}}' \$(docker ps -q --filter name=$APP | head -1)"
BODY='{}'; curl -s -o /dev/null -w '%{http_code}\n' -X POST -H 'X-GitHub-Event: pull_request' -H 'X-Hub-Signature-256: sha256=00' -d "$BODY" https://$BOT_HOST/github
```

Success: `healthy`; `401` (an unsigned request refused). Then ask the person to look at the dashboard channel twice,
a minute apart: one message, its time moving. Ask them to merge a small pull request in one of `CONTENT_REPOS` and
tell you when; the changelog channel should get one post within seconds, and that repository's latest delivery
reads `pull_request 200`. The buttons are the person's to press, at a quiet time (chapter step 7).

## Roll back

Stop the bot: `cl POST /applications/$APP/stop`. The dashboard message stays, frozen; the person can delete it in
Discord. Remove the changelog webhooks with `gh api -X DELETE repos/<repo>/hooks/<id>` (ids from `gh api
repos/<repo>/hooks -q '.[] | "\(.id) \(.config.url)"'`), and the deploy-on-merge webhook the same way on `BOT_REPO`.
A bad change to the bot itself: revert it on `BOT_REPO`; the merge redeploys the previous code.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- steps 1, 3, 4 and 5, always;
- pressing **Restart** or **Cancel restart**, or running `/restart` or `/cancel-restart`;
- any key in `OPS_API_KEY` other than the team key;
- turning `SYNC_COMMANDS` on for a token that another program also runs on (the sync replaces that application's
  commands in the server);
- printing, copying or moving `BOT_ENV` anywhere but into Coolify;
- deleting the application, its deploy key or a webhook.
