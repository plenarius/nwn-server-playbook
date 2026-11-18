# Playbook 7, tier 2. Content built and served from the control host

For an agent. The chapter for people is [`chapters/07-haks-nwsync.md`](../chapters/07-haks-nwsync.md), section
"Tier 2". Follow the steps in order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `GAME` | The game host's public address | none: a person gives it |
| `CONTROL` | The control host's public address | none: a person gives it |
| `DEPLOY_USER` | The deploy user on both machines | `nwn` |
| `GAME_WG` | The game host's private address | `10.77.0.2` |
| `NWSYNC_HOST` | The name players download from, already serving from the game host | none: a person gives it |
| `CONTENT_REPO` | The content repository's SSH address, such as `git@github.com:you/myhaks.git` | none: a person gives it |
| `MODULE` | The module file to publish for, on the person's computer | none: a person gives it |

Secrets: `COOLIFY_TOKEN` (Root), placed by a person as in playbook 3. The control host's private key is made there
and never leaves it. Never print an API response for a service.

## Preconditions

```sh
ssh -f -N -L 8000:localhost:8000 $DEPLOY_USER@$CONTROL 2>/dev/null
cl() { curl -s -X "$1" -H @<(printf 'Authorization: Bearer %s\n' "$COOLIFY_TOKEN") -H 'Content-Type: application/json' ${3:+-d "$3"} "http://localhost:8000/api/v1$2"; }
LOCALSRV=$(cl GET /servers | python3 -c 'import json,sys; print([s["uuid"] for s in json.load(sys.stdin) if not s["ip"].startswith("10.")][0])'); echo $LOCALSRV
curl -s -m 10 https://$NWSYNC_HOST/latest; echo
ssh $DEPLOY_USER@$CONTROL "ping -c1 -W2 $GAME_WG >/dev/null && echo 'private network ok'; ls -d ~/nwsync ~/myhaks 2>/dev/null | wc -l"
```

Success: an id; a 40-character version; `private network ok`; `0`. If `~/nwsync` or `~/myhaks` exists, stop and
ask.

## Steps

### 1. Tools and the control host's key

```sh
ssh $DEPLOY_USER@$CONTROL 'sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unzip >/dev/null && mkdir -p ~/nwn-tools && cd ~/nwn-tools && curl -fsSL -o nw.zip https://github.com/niv/neverwinter.nim/releases/download/2.3.2/neverwinter-x86_64-linux-gnu.zip && unzip -oq nw.zip && rm nw.zip && ls nwn_nwsync_write nwn_nwsync_prune nwn_erf nwn_tlk | wc -l; test -e ~/.ssh/id_ed25519 || ssh-keygen -q -t ed25519 -N "" -C "nwn@control" -f ~/.ssh/id_ed25519; cat ~/.ssh/id_ed25519.pub'
```

Success: `4`, then one public key line.

**Ask the person** to add that line to the content repository on GitHub as a **read-only** deploy key (Settings,
Deploy keys). Wait until they say it's done. If they want you to do it and `gh` is signed in for that repository:

```sh
gh api repos/OWNER/REPO/keys -f title=control-host -f key="$(ssh $DEPLOY_USER@$CONTROL cat .ssh/id_ed25519.pub)" -F read_only=true -q .read_only
```

Success: `true`.

### 2. The game host accepts the key; the clone and a build

```sh
ssh $DEPLOY_USER@$CONTROL cat .ssh/id_ed25519.pub | ssh $DEPLOY_USER@$GAME 'cat >> ~/.ssh/authorized_keys'
ssh $DEPLOY_USER@$CONTROL "ssh -o StrictHostKeyChecking=accept-new $DEPLOY_USER@$GAME_WG hostname && ssh-keyscan -q github.com >> ~/.ssh/known_hosts 2>/dev/null && git clone -q $CONTENT_REPO ~/myhaks && cd ~/myhaks && PATH=~/nwn-tools:\$PATH ./build.sh 2>&1 | grep -v 'erf header'"
```

Success: the game host's name, then a `packed` line per hak and a `built` line per talk table.

### 3. The download folder, the script and the module

```sh
ssh $DEPLOY_USER@$CONTROL "mkdir -p ~/nwsync ~/content && rsync -a $DEPLOY_USER@$GAME_WG:game/nwsync/ ~/nwsync/ && cat ~/nwsync/latest && echo"
scp templates/content/Caddyfile templates/content/publish.sh "$MODULE" $DEPLOY_USER@$CONTROL:content/
ssh $DEPLOY_USER@$CONTROL 'chmod +x content/publish.sh && ls content'
```

Success: the same version as in the preconditions; `Caddyfile`, `publish.sh` and the module.

### 4. The downloads service, not started

```sh
PROJ=$(cl POST /projects '{"name":"web"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["uuid"])')
DL=$(cl POST /services "{\"project_uuid\":\"$PROJ\",\"server_uuid\":\"$LOCALSRV\",\"environment_name\":\"production\",\"name\":\"downloads\",\"docker_compose_raw\":\"$(sed "s|/home/nwn/|/home/$DEPLOY_USER/|g" templates/content/downloads.yaml | base64 -w0)\"}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["uuid"])'); echo $DL
cl PATCH /services/$DL "{\"urls\":[{\"name\":\"downloads\",\"url\":\"https://$NWSYNC_HOST\"}]}" | python3 -c 'import json,sys; print("domain set" if "uuid" in json.load(sys.stdin) else "FAILED")'
```

Success: an id, then `domain set`.

**Ask the person** to open TCP 80 and 443 to everyone at the control host's provider firewall. Wait for their yes.

### 5. Move the name, then deploy

**Ask first.** The name moves to `CONTROL`, which costs one certificate (at most five a week for the same name).
Then the person moves the record, or you do with playbook 2's `move` after their yes. Check at the source:

```sh
NS=$(dig +short NS ${NWSYNC_HOST#*.} | head -1); dig +short $NWSYNC_HOST @$NS | tail -1
```

Success: `CONTROL`. Only then:

```sh
DL=$(cl GET /services | python3 -c 'import json,sys; r=[s["uuid"] for s in json.load(sys.stdin) if s["name"]=="downloads"]; print(r[0] if len(r)==1 else "")'); echo "service: ${DL:-none or several}"
cl POST "/deploy?uuid=$DL&force=false" > /dev/null; sleep 45
curl -s -m 10 https://$NWSYNC_HOST/latest; echo
echo | openssl s_client -connect $NWSYNC_HOST:443 -servername $NWSYNC_HOST 2>/dev/null | openssl x509 -noout -issuer
```

Success: one service id, the version from step 3, and an issuer naming Let's Encrypt. If the certificate is missing after two
minutes, run `docker restart coolify-proxy` on the control host once and check again. Never go on to step 6 while
this check fails.

### 6. Restart the game once

**Ask first**: players are disconnected for about 20 seconds. Then the person presses **Restart** on the game
service in Coolify, or you do with `cl POST /services/<the game service's uuid>/restart` after their yes.

```sh
sleep 60; ssh $DEPLOY_USER@$GAME 'docker logs $(docker ps -q --filter label=com.docker.compose.service=nwserver) 2>&1 | grep -a NWSync | tail -2'
```

Success: a line naming `https://NWSYNC_HOST/latest` and `We're now advertising` with the version from step 3.

### 7. The game host's web server off

If `~/game/sites` on the game host holds any file besides `nwsync.caddy`, stop and ask: a website still runs there.
Otherwise:

```sh
ssh $DEPLOY_USER@$GAME 'cd game && docker compose stop caddy 2>&1 | tail -1 && docker compose rm -f caddy 2>&1 | tail -1 && sed -i "s|^COMPOSE_FILE=.*|COMPOSE_FILE=compose.yaml:compose.db.yaml|" .env && grep ^COMPOSE_FILE .env && (sudo ss -tlnp | grep -E ":(80|443) " || echo "nothing on 80 or 443")'
```

Success: the `COMPOSE_FILE` line and `nothing on 80 or 443`.

Coolify starts its own proxy on the game host at the game's next restart unless it is stopped in the dashboard, and
there is no API for that. **Ask the person** to open the game host's **Proxy** page in Coolify, choose **More
actions**, **Stop Proxy**, and confirm, and to close 80 and 443 at the game host's provider firewall. Wait for
their yes, then check:

```sh
ssh $DEPLOY_USER@$GAME 'docker ps --format "{{.Names}}" | grep -c coolify-proxy'
```

Success: `0`.

## Verify

```sh
ssh $DEPLOY_USER@$CONTROL "~/content/publish.sh ~/content/$(basename "$MODULE")"
```

Success: `published` with a version, `sent to`, and `kept: ...`. Nothing is released by this; tell the person the
files wait in `~/incoming` on the game host for `release.sh`, which is theirs to run (chapter 16).

## Roll back

Until step 7, the game host still serves the old way: move the name back to `GAME`, and stop the downloads service
(`cl POST /services/$DL/stop`). After step 7, also start Caddy again on the game host with the old `COMPOSE_FILE`
line (`compose.yaml:compose.db.yaml:compose.web.yaml`). A move back costs another certificate.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- step 5 (the name) and step 6 (the restart), always;
- a failed check in step 5: never restart the game while the download address isn't working;
- running `release.sh`;
- deleting anything in `~/nwsync` by hand, or in `~/game/nwsync` on the game host.
