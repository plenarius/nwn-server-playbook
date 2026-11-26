# Playbook 7, tier 2. Content built and served from the control host, staged and promoted

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
| `IMAGE` | The builder image's name, after the tools' version in `templates/content/builder/Dockerfile` | `nwsync-builder:2.3.2` |

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

### 1. The control host's key

```sh
ssh $DEPLOY_USER@$CONTROL 'test -e ~/.ssh/id_ed25519 || ssh-keygen -q -t ed25519 -N "" -C "nwn@control" -f ~/.ssh/id_ed25519; cat ~/.ssh/id_ed25519.pub'
```

Success: one public key line.

**Ask the person** to add that line to the content repository on GitHub as a **read-only** deploy key (Settings,
Deploy keys). Wait until they say it's done. If they want you to do it and `gh` is signed in for that repository:

```sh
gh api repos/OWNER/REPO/keys -f title=control-host -f key="$(ssh $DEPLOY_USER@$CONTROL cat .ssh/id_ed25519.pub)" -F read_only=true -q .read_only
```

Success: `true`.

### 2. The game host accepts the key; the clone

```sh
ssh $DEPLOY_USER@$CONTROL cat .ssh/id_ed25519.pub | ssh $DEPLOY_USER@$GAME 'cat >> ~/.ssh/authorized_keys'
ssh $DEPLOY_USER@$CONTROL "ssh -o StrictHostKeyChecking=accept-new $DEPLOY_USER@$GAME_WG hostname && ssh-keyscan -q github.com >> ~/.ssh/known_hosts 2>/dev/null && git clone -q $CONTENT_REPO ~/myhaks && ls ~/myhaks"
```

Success: the game host's name, then the repository's files, `build.sh` among them.

### 3. The download folder, the scripts, the image and a build

```sh
ssh $DEPLOY_USER@$CONTROL "mkdir -p ~/nwsync ~/content && rsync -a $DEPLOY_USER@$GAME_WG:game/nwsync/ ~/nwsync/ && cat ~/nwsync/latest && echo"
scp -q -r templates/content/* "$MODULE" $DEPLOY_USER@$CONTROL:content/
ssh $DEPLOY_USER@$CONTROL "cd ~/content && (test -e content.env || cp content.env.example content.env) && sed -i 's|^NWSYNC_URL=.*|NWSYNC_URL=https://$NWSYNC_HOST|' content.env && grep ^NWSYNC_URL content.env && docker build -q -t $IMAGE builder > /dev/null && docker run --rm --user \$(id -u):\$(id -g) -v ~/myhaks:/src $IMAGE /src/build.sh 2>&1 | grep -v 'erf header'"
```

Success: the same version as in the preconditions; the `NWSYNC_URL` line with `NWSYNC_HOST`; a `packed` line per
hak and a `built` line per talk table.

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

### 8. Stage the content

Nothing reaches players in this step: `latest` is not touched.

```sh
ssh $DEPLOY_USER@$CONTROL "~/content/publish.sh ~/content/$(basename "$MODULE")"
```

Success: `written`, a line `Entries: ... Size: ...`, `checked: https://NWSYNC_HOST hands out ... completely`,
`sent ... files to ...:incoming, checked`, `staged` with a version, and `players still get` with the version from
step 3. Any other ending is a failed check: report its line and stop.

### 9. Promote

**Ask first**: this is a release. Players are disconnected for a few seconds, and chapter 16's steps 1 to 4 (merged,
plugin check, NWNX versions, players told) are the person's. After their yes:

```sh
ssh $DEPLOY_USER@$CONTROL '~/content/promote.sh'
```

Success: `latest is <staged> (was <old>)`, `the game is healthy again`, `the game hands out <staged>`, and a `kept:`
line. If it ends with `the release failed`, stop and hand back with the output; don't run `--back` without the
person.

## Verify

```sh
V=$(ssh $DEPLOY_USER@$GAME 'docker logs $(docker ps -q --filter label=com.docker.compose.service=nwserver) 2>&1 | grep -a "now advertising" | tail -1 | grep -o "[0-9a-f]\{40\}"'); echo "game: $V"
curl -s https://$NWSYNC_HOST/latest; echo
ssh $DEPLOY_USER@$CONTROL "docker run --rm $IMAGE nwsync-check https://$NWSYNC_HOST $V"
```

Success: the same version three times (the game, `latest`, and the version checked), and `Entries: ... Size: ...`.

## Roll back

After step 9, going back to the version before is one command; **ask first**, as it restarts the game:

```sh
ssh $DEPLOY_USER@$CONTROL '~/content/promote.sh --back'
```

Success: `latest is <old> again`, `the game is healthy again`, `the game hands out <old>`. It works once, for the
last promote, and only if no module-only release happened since (it uses `release.sh --undo`).

Before step 9, nothing reached players: a staged version needs no rollback, and the next `publish.sh` replaces it.

Until step 7, the game host still serves the old way: move the name back to `GAME`, and stop the downloads service
(`cl POST /services/$DL/stop`). After step 7, also start Caddy again on the game host with the old `COMPOSE_FILE`
line (`compose.yaml:compose.db.yaml:compose.web.yaml`). A move back costs another certificate.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- step 5 (the name), step 6 (the restart), step 9 (the promote) and `promote.sh --back`, always;
- a failed check in step 5: never restart the game while the download address isn't working;
- running `release.sh` by hand;
- running `prune.sh` by hand, or deleting anything in `~/nwsync` by hand, or in `~/game/nwsync` on the game host;
- changing the tools' version or checksum in the `Dockerfile`, or removing a builder image.
