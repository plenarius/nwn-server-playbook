# Playbook 14, tier 3. Loading from chat, and custom content of its own

For an agent. The chapter for people is [`chapters/14-dev-server.md`](../chapters/14-dev-server.md), section
"Tier 3". Follow the steps in order. Do not go on from a step whose check fails.

`GUIDE` is the root of this repository on the person's computer. Run every command there unless it says otherwise.
`cl` is the Coolify API helper from playbook 3 (`cl METHOD PATH [JSON]`, the token never printed).

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `GUIDE` | Where this repository is | none: a person gives it |
| `CONTROL` | The control host's public address | none: a person gives it |
| `CONTROL_WG` | The control host's private address | `10.77.0.1` |
| `DEPLOY_USER` | The deploy user | `nwn` |
| `GH_REPO` | The module's repository, `owner/name` | none: a person gives it |
| `REPO_DIR` | A checkout of it on this computer | `~/mymodule` |
| `BOT_DIR` | A checkout of the bot's repository (playbook 10) | `~/mybot` |
| `DEV_HOST` | The dev download name, never the live one | none: a person gives it |
| `LIVE_URL` | The live download address (chapter 7's `NWSYNC_URL`) | from `~/content/content.env` |
| `DEV_SVC` | Coolify's id for the `dev` service (tier 2) | from `cl GET /services` |
| `DEV_ROLE_ID` | The Discord builders' role id | none: a person gives it |

Secrets: the workflow's key is made in step 3 into a private temporary folder and goes only to the control host
(public half) and to the repository's secrets (private half), then is deleted. The operations API's GitHub token and
the bot's settings are changed by a person in Coolify; never print them. Read API keys from
`~/ops-api/keys/*` on the control host inside the command that uses them; never print them.

## Preconditions

```sh
ssh $DEPLOY_USER@$CONTROL 'cd dev && ./dev.sh status | sed -n "1p;\$p"; cat ~/nwsync/latest; echo; grep ^NWSYNC_URL ~/content/content.env; ls ~/myhaks/build/hak | head -3'
gh run list -R $GH_REPO -w "Compile check" -b main -L 1 --json conclusion -q '.[0].conclusion'
ssh $DEPLOY_USER@$CONTROL 'curl -s -o /dev/null -w "%{http_code}\n" 10.77.0.1:8100/health'
ssh $DEPLOY_USER@$CONTROL 'cd ~/nwsync && find . -type f -o -type l | sort | xargs sha256sum | sha256sum' | tee /tmp/live-nwsync.txt
```

Success: `loaded: ... main-...` and `game: healthy`; a 40-character version; the `NWSYNC_URL` line (`LIVE_URL`);
at least one `.hak`; `success`; `200`; a checksum line (kept for Verify). If `DEV_HOST` is the host in `LIVE_URL`,
stop and ask.

## Steps

### 1. The dev server's new parts

```sh
ssh $DEPLOY_USER@$CONTROL 'mkdir -p ~/dev/home/hak ~/dev/home/tlk ~/dev/nwsync ~/dev/content/hak ~/dev/status'
scp -p templates/dev/dev.sh templates/dev/dev-content.sh templates/dev/Caddyfile.dev $DEPLOY_USER@$CONTROL:dev/
ssh $DEPLOY_USER@$CONTROL 'stat -c "%U %A %n" ~/dev/nwsync ~/dev/dev-content.sh; df --output=target ~/dev/nwsync ~/nwsync | tail -2 | uniq | wc -l'
```

Success: the deploy user owning both, `-rwx` on `dev-content.sh`, and `1` (the same disk).

### 2. The service, and the name

**Ask first** before creating the record: the person adds an address record for `DEV_HOST` pointing at `CONTROL`
(or you do with playbook 2's `create` after their yes). Then:

```sh
cl PATCH /services/$DEV_SVC "{\"docker_compose_raw\":\"$(sed "s|/home/nwn/|/home/$DEPLOY_USER/|g" templates/dev/dev.yaml | base64 -w0)\"}" | python3 -c 'import json,sys; print("compose set" if "uuid" in json.load(sys.stdin) else "FAILED")'
cl PATCH /services/$DEV_SVC/envs "{\"key\":\"NWN_NWSYNCURL\",\"value\":\"https://$DEV_HOST\"}" | python3 -c 'import json,sys; print("setting set" if "uuid" in json.load(sys.stdin) else "FAILED")'
cl PATCH /services/$DEV_SVC "{\"urls\":[{\"name\":\"dev-downloads\",\"url\":\"https://$DEV_HOST\"}]}" | python3 -c 'import json,sys; print("domain set" if "uuid" in json.load(sys.stdin) else "FAILED")'
cl POST "/deploy?uuid=$DEV_SVC&force=false" > /dev/null; sleep 60
curl -s https://$DEV_HOST/latest; echo; curl -s $LIVE_URL/latest; echo
```

Success: `compose set`, `setting set` (if it says FAILED because the setting is new, use `POST` instead of `PATCH`),
`domain set`, then the same version twice. If the dev address doesn't answer after two minutes, run
`docker restart coolify-proxy` on the control host once and check again.

### 3. The workflow, its key and its settings

**Ask first** before adding a key to the control host.

```sh
K=$(mktemp -d); ssh-keygen -q -t ed25519 -N '' -C dev-loader-actions -f $K/key
{ printf 'command="/home/%s/dev/dev.sh \\"$SSH_ORIGINAL_COMMAND\\"",restrict ' $DEPLOY_USER; cat $K/key.pub; } | ssh $DEPLOY_USER@$CONTROL 'cat >> ~/.ssh/authorized_keys'
gh secret set DEV_KEY -R $GH_REPO < $K/key && rm -rf $K
gh variable set DEV_CONTROL -R $GH_REPO -b "$DEPLOY_USER@$CONTROL"
ssh-keyscan -t ed25519 $CONTROL 2>/dev/null | grep -v '^#' > /tmp/dev-hostkey; ssh-keygen -lf /tmp/dev-hostkey | cut -d' ' -f2
ssh $DEPLOY_USER@$CONTROL 'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub | cut -d" " -f2'
```

Success: the same `SHA256:...` twice; if they differ, stop and ask. Then:

```sh
gh variable set DEV_HOST_KEY -R $GH_REPO -b "$(cat /tmp/dev-hostkey)"
cp templates/dev/load-build.sh $REPO_DIR/tools/ && cp templates/dev/dev-load.yml $REPO_DIR/.github/workflows/
cd $REPO_DIR && git checkout -b dev-load && git add tools/load-build.sh .github/workflows/dev-load.yml && git commit -qm "Dev load workflow" && git push -q -u origin dev-load && gh pr create -f
```

Success: a pull request link. **Stop and ask** the person to review and merge it. After the merge:

```sh
gh workflow run "Dev load" -R $GH_REPO -f target=main -f requested_by=agent; sleep 60
gh run list -R $GH_REPO -w "Dev load" -L 1 --json conclusion -q '.[0].conclusion'
```

Success: `success`.

### 4. A builder's hak

Use a hak the person names (`HAK`, a `.hak` file a builder gave you), with a builder's key from tier 2 (`lb` is tier
2's function):

```sh
lb hak $HAK | tail -2
lb hak-remove $(basename $HAK .hak) | tail -1
```

Success: `dev content <version>: <name>, ...` and `dev server is healthy with <name>.hak`, then `dev server is
healthy without its own <name>.hak`.

### 5. The operations API

**Stop and ask.** The person adds **Actions: Read and write** on `GH_REPO` to the API's GitHub token, deploys a
version of the API with the dev routes, takes the `#` off the dev status mount in the API's compose file, and sets
`DEV_REPO=$GH_REPO` and `DEV_STATUS_FILE=/dev-status/status.json` in Coolify. Then:

```sh
ssh $DEPLOY_USER@$CONTROL 'curl -s -H "Authorization: Bearer $(cat ~/ops-api/keys/read)" 10.77.0.1:8100/api/v1/dev/status | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[\"loaded\"][\"label\"], d[\"loaded\"][\"health\"], d[\"last_run\"][\"conclusion\"])"'
ssh $DEPLOY_USER@$CONTROL 'curl -s -o /dev/null -w "%{http_code}\n" -X POST -H "Authorization: Bearer $(cat ~/ops-api/keys/read)" -H "Content-Type: application/json" -d "{\"target\":\"main\"}" 10.77.0.1:8100/api/v1/dev/load'
ssh $DEPLOY_USER@$CONTROL '(crontab -l 2>/dev/null | grep -v "dev/dev.sh status"; echo "*/5 * * * * \$HOME/dev/dev.sh status > /dev/null 2>&1") | crontab - && crontab -l | grep -c dev.sh'
```

Success: `main-... healthy success`; `403`; `1`.

### 6. The bot

Bring `bot/dev.py`, `tests/test_dev.py` and the changes to `bot/ops_api.py`, `bot/settings.py`, `bot/__main__.py`
and `.env.example` from `templates/bot` into `BOT_DIR` on a branch, and run the tests:

```sh
cd $BOT_DIR && python -m pytest -q tests/test_dev.py | tail -1
```

Success: `5 passed`. Open a pull request with `gh pr create -f`. **Stop and ask** the person to merge it and to add
`DEV_ROLE_ID=$DEV_ROLE_ID` in the bot's settings in Coolify, then deploy. Ask them to run `/dev status` in Discord
and tell you the line they see.

## Verify

```sh
ssh $DEPLOY_USER@$CONTROL 'cd dev && ./dev.sh status'
curl -s https://$DEV_HOST/latest; echo
ssh $DEPLOY_USER@$CONTROL 'cd ~/nwsync && find . -type f -o -type l | sort | xargs sha256sum | sha256sum' | diff - /tmp/live-nwsync.txt && echo "live content untouched"
ssh $DEPLOY_USER@$CONTROL 'python3 -m json.tool ~/dev/status/status.json | grep -E "\"(label|commit|content|health)\""'
```

Success: `loaded:`, `content:` and `game: healthy` lines; the version in `content:`; `live content untouched`; the
same label, commit and content in the status file. The person's `/dev status` line names the same build.

## Roll back

- **The bot:** remove `DEV_ROLE_ID` in Coolify and deploy; `/dev` disappears at the next command sync.
- **The API:** remove `DEV_REPO` and `DEV_STATUS_FILE` and the mount; the dev routes answer `503`. Take Actions write
  off the token.
- **The workflow:** delete `.github/workflows/dev-load.yml` (a pull request), the `DEV_KEY` secret, the two variables,
  and the `dev-loader-actions` line in the control host's `~/.ssh/authorized_keys`.
- **The dev content:** remove `NWN_NWSYNCURL` from the dev service, paste tier 2's `dev.yaml` back, deploy, then
  `rm -rf ~/dev/nwsync ~/dev/content ~/dev/home/hak ~/dev/home/tlk` on the control host and delete the `DEV_HOST`
  record. Nothing live reads any of it.
- The crontab line: `crontab -e` and delete it.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- `DEV_HOST` equal to the live download name, or any step that would write to `~/nwsync`, `~/myhaks` or the game host;
- creating the `DEV_HOST` record, adding any key, a host key fingerprint that doesn't match;
- merging any pull request, changing the API's token or settings, changing the bot's settings;
- loading a pull request from a fork, or one the person hasn't named;
- `live content untouched` failing in Verify;
- printing any key, token or password.
