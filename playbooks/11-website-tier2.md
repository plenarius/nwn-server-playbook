# Playbook 11, tier 2. The website on the control host, deployed on merge

For an agent. The chapter for people is [`chapters/11-website.md`](../chapters/11-website.md), section "Tier 2".
Follow the steps in order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer, with `gh` signed in as someone who
may change the site's repository settings.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `GAME` | The game host's public address | none: a person gives it |
| `CONTROL` | The control host's public address | none: a person gives it |
| `DEPLOY_USER` | The deploy user on both machines | `nwn` |
| `SITE_REPO` | The site's private GitHub repository, as `owner/name` | none: a person gives it |
| `SITE_DIR` | The folder in it that holds the `Dockerfile`, starting with `/` | `/` |
| `SITE_HOST` | The site's name, such as `www.example.org` | none: a person gives it |

Secrets: `COOLIFY_TOKEN` (Root), placed by a person as in playbook 3. The deploy key's private half goes from a
private temporary file straight into Coolify and is then deleted; the webhook secret lives only in a shell variable.
Never print either, and never print an API response for an application.

## Preconditions

```sh
ssh -f -N -L 8000:localhost:8000 $DEPLOY_USER@$CONTROL 2>/dev/null
cl() { curl -s -X "$1" -H @<(printf 'Authorization: Bearer %s\n' "$COOLIFY_TOKEN") -H 'Content-Type: application/json' ${3:+-d "$3"} "http://localhost:8000/api/v1$2"; }
LOCALSRV=$(cl GET /servers | python3 -c 'import json,sys; print([s["uuid"] for s in json.load(sys.stdin) if not s["ip"].startswith("10.")][0])'); echo $LOCALSRV
gh repo view $SITE_REPO --json visibility -q .visibility
gh api "repos/$SITE_REPO/contents${SITE_DIR%/}/Dockerfile" -q .name
cl GET /applications | python3 -c 'import json,sys; print(sum(1 for a in json.load(sys.stdin) if a["name"]=="website"), "applications named website")'
NS=$(dig +short NS ${SITE_HOST#*.} | head -1); dig +short $SITE_HOST @$NS | tail -1
```

Success: an id; `PRIVATE`; `Dockerfile`; `0 applications named website`; then either `GAME` (the tier 1 site) or
nothing (no record yet). Anything else: stop and ask.

## Steps

### 1. A deploy key

**Ask first**: this adds a read-only deploy key to `SITE_REPO`. After the yes:

```sh
umask 077; T=$(mktemp -d)
ssh-keygen -q -t ed25519 -N '' -C coolify-website -f $T/key
gh api repos/$SITE_REPO/keys -f title=coolify-website -f key="$(cat $T/key.pub)" -F read_only=true -q .read_only
KEY=$(python3 -c 'import json,sys; print(json.dumps({"name":"website-deploy","private_key":open(sys.argv[1]).read()}))' $T/key | cl POST /security/keys "$(cat)" | python3 -c 'import json,sys; print(json.load(sys.stdin)["uuid"])'); rm -r $T; echo $KEY
```

Success: `true`, then an id.

### 2. The application, not deployed

```sh
PROJ=$(cl GET /projects | python3 -c 'import json,sys; r=[p["uuid"] for p in json.load(sys.stdin) if p["name"]=="web"]; print(r[0] if r else "")')
[ -n "$PROJ" ] || PROJ=$(cl POST /projects '{"name":"web"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["uuid"])')
APP=$(cl POST /applications/private-deploy-key "{\"project_uuid\":\"$PROJ\",\"server_uuid\":\"$LOCALSRV\",\"environment_name\":\"production\",\"private_key_uuid\":\"$KEY\",\"git_repository\":\"git@github.com:$SITE_REPO.git\",\"git_branch\":\"main\",\"build_pack\":\"dockerfile\",\"base_directory\":\"${SITE_DIR:-/}\",\"ports_exposes\":\"80\",\"domains\":\"https://$SITE_HOST\",\"name\":\"website\",\"instant_deploy\":false}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("uuid") or "FAILED")'); echo $APP
```

Success: an id.

**Ask the person** to open TCP 80 and 443 to everyone at the control host's provider firewall, if they aren't open
already. Wait for their yes.

### 3. Move the name, then deploy

**Ask first.** `SITE_HOST` moves to (or is made for) `CONTROL`, which costs one certificate (at most five a week for
the same name). The person changes the record, or you do with playbook 2 after their yes. Check at the source:

```sh
NS=$(dig +short NS ${SITE_HOST#*.} | head -1); dig +short $SITE_HOST @$NS | tail -1
```

Success: `CONTROL`. Only then:

```sh
APP=$(cl GET /applications | python3 -c 'import json,sys; r=[a["uuid"] for a in json.load(sys.stdin) if a["name"]=="website"]; print(r[0] if len(r)==1 else "")'); echo "application: ${APP:-none or several}"
cl POST "/deploy?uuid=$APP&force=false" > /dev/null
for i in $(seq 40); do st=$(cl GET "/deployments/applications/$APP?take=1" | python3 -c 'import json,sys; d=json.load(sys.stdin); d=d.get("deployments",d) if isinstance(d,dict) else d; print(d[0]["status"] if d else "none")'); [ "$st" = finished ] || [ "$st" = failed ] && break; sleep 6; done; echo "deploy: $st"
sleep 20; curl -s -m 10 https://$SITE_HOST/ | grep -o '<title>[^<]*'
echo | openssl s_client -connect $SITE_HOST:443 -servername $SITE_HOST 2>/dev/null | openssl x509 -noout -issuer
```

Success: one id, `deploy: finished`, the site's title, and an issuer naming Let's Encrypt. If the deploy finished
but the certificate is missing after two minutes, run `docker restart coolify-proxy` on the control host once and
check again.

### 4. The webhook

**Ask first**: this adds a webhook to `SITE_REPO`, pointing at `CONTROL` on port 8000. After the yes:

```sh
APP=$(cl GET /applications | python3 -c 'import json,sys; r=[a["uuid"] for a in json.load(sys.stdin) if a["name"]=="website"]; print(r[0] if len(r)==1 else "")'); echo "application: ${APP:-none or several}"
SECRET=$(openssl rand -hex 20)
cl PATCH /applications/$APP "{\"manual_webhook_secret_github\":\"$SECRET\"}" | python3 -c 'import json,sys; print("secret set" if "uuid" in json.load(sys.stdin) else "FAILED")'
HOOK=$(gh api repos/$SITE_REPO/hooks -f name=web -F active=true -f 'events[]=push' -f "config[url]=http://$CONTROL:8000/webhooks/source/github/events/manual" -f config[content_type]=json -f "config[secret]=$SECRET" -q .id); unset SECRET
sleep 10; gh api repos/$SITE_REPO/hooks/$HOOK/deliveries -q '.[0] | "\(.event) \(.status_code)"'
```

Success: one id, `secret set`, then `ping 200`. Anything other than 200: the control host's provider firewall may not let
GitHub through to port 8000 (chapter 3, step 9); stop and ask.

### 5. The old site on the game host

```sh
ssh $DEPLOY_USER@$GAME 'ls ~/game/sites 2>/dev/null'
```

If `www.caddy` isn't listed, there is nothing to switch off; go to Verify. Otherwise **ask first**, then:

```sh
ssh $DEPLOY_USER@$GAME 'cd game && rm sites/www.caddy && sed -i "/^SITE_HOST=/d" .env && if [ -e sites/nwsync.caddy ]; then docker compose up -d caddy 2>&1 | tail -1; else echo "sites is empty: switch the web server off with playbook 7, tier 2, step 7"; fi'
```

## Verify

Ask the person to merge a small change to the site, and tell you when. Then:

```sh
APP=$(cl GET /applications | python3 -c 'import json,sys; r=[a["uuid"] for a in json.load(sys.stdin) if a["name"]=="website"]; print(r[0] if len(r)==1 else "")'); echo "application: ${APP:-none or several}"
for i in $(seq 20); do st=$(cl GET "/deployments/applications/$APP?take=1" | python3 -c 'import json,sys; d=json.load(sys.stdin); d=d.get("deployments",d) if isinstance(d,dict) else d; print(d[0]["status"] if d else "none")'); [ "$st" = finished ] && break; sleep 6; done; echo "deploy: $st"
curl -s -m 10 https://$SITE_HOST/ | grep -o '<title>[^<]*'
```

Success: `deploy: finished`, and the person sees their change on the site.

## Roll back

Point `SITE_HOST` back at `GAME`, and on the game host put `sites/www.caddy` and the `SITE_HOST` line back and run
`docker compose up -d caddy`. Then stop the application in Coolify (`cl POST /applications/$APP/stop`). The tier 1
folder `~/game/site` still holds the page as it was before the move.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- steps 1, 3, 4 and 5, always;
- a repository that isn't private, or has no `Dockerfile` where `SITE_DIR` says;
- deleting the application, its deploy key or the webhook.
