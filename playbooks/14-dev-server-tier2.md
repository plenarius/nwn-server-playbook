# Playbook 14, tier 2. A dev server

For an agent. The chapter for people is [`chapters/14-dev-server.md`](../chapters/14-dev-server.md), section
"Tier 2". Follow the steps in order. Do not go on from a step whose check fails.

Tier 1 has no dev server and no playbook. This tier is optional: before step 1, ask the person whether they want
one (the chapter's "What you learn" says who does).

`GUIDE` is the root of this repository on the person's computer. Run every command there unless it says otherwise.
`cl` is the Coolify API helper from playbook 3 (`cl METHOD PATH [JSON]`, the token never printed).

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `GUIDE` | Where this repository is | none: a person gives it |
| `CONTROL` | The control host's public address | none: a person gives it |
| `GAME` | The game host's public address | none: a person gives it |
| `CONTROL_WG` | The control host's private address | `10.77.0.1` |
| `GAME_WG` | The game host's private address | `10.77.0.2` |
| `DEPLOY_USER` | The deploy user on both machines | `nwn` |
| `LOCALSRV` | Coolify's id for the control host itself (`localhost`) | from `cl GET /servers` |
| `GH_REPO` | The module's repository, `owner/name` | none: a person gives it |
| `MODULE_NAME` | The module's name, as live's `NWN_MODULE` | `mymodule` |
| `DEV_PORT` | The dev game's UDP port on the control host | `5121` |
| `BUILDERS` | The builders' addresses, for the firewall | none: a person gives them |
| `PR` | A pull request to load in step 6 | none: a person gives it |

Secrets: the dev game's passwords are typed by a person into Coolify (step 3), or made by you in step 3 into a
private temporary file that goes only to Coolify and is then deleted; never print them. The builder's key is made
on the builder's own computer. The dump key is made on the control host and never leaves it. You never read
`scrub.list` values from the live database: you read column names only.

## Preconditions

```sh
ssh $DEPLOY_USER@$CONTROL 'docker ps --format "{{.Label \"com.docker.compose.service\"}}" | grep -c "^dev-"; ls -d ~/dev 2>/dev/null | wc -l; ping -c1 -W2 '$GAME_WG' | grep -c " 0% packet loss"'
ssh $DEPLOY_USER@$GAME 'ls -d game/backups/*/ | tail -1; docker ps --format "{{.Label \"com.docker.compose.service\"}}" | sort | tr "\n" " "'
gh run list -R $GH_REPO -w "Compile check" -b main -L 1 --json conclusion -q '.[0].conclusion'
cl GET /servers | python3 -c 'import json,sys; [print(s["name"], s["uuid"], s["settings"]["is_usable"]) for s in json.load(sys.stdin)]'
```

Success: `0`, `0`, `1` (no dev server yet, no `~/dev`, the private network up); a backup folder less than a day old
and services including `mariadb nwserver`; `success`; a `localhost` line with `True` (its id is `LOCALSRV`). If a
`dev-` service or `~/dev` exists, stop and ask.

Record the live game's start time, to compare in Verify:

```sh
ssh $DEPLOY_USER@$GAME 'docker inspect -f "{{.State.StartedAt}}" $(docker ps -q --filter label=com.docker.compose.service=nwserver)' | tee /tmp/live-started.txt
```

## Steps

### 1. Folders and scripts

```sh
ssh $DEPLOY_USER@$CONTROL 'mkdir -p ~/dev/home/modules ~/dev/db ~/dev/logs' && scp templates/dev/dev.sh templates/dev/copy-db.sh templates/dev/scrub.list.example $DEPLOY_USER@$CONTROL:dev/
ssh $DEPLOY_USER@$CONTROL 'stat -c "%U %n" ~/dev/home/modules; ls ~/dev'
```

Success: `nwn /home/nwn/dev/home/modules` (the deploy user), and `copy-db.sh db dev.sh home logs scrub.list.example`.

### 2. The service

```sh
PROJ=$(cl POST /projects '{"name":"dev"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["uuid"])')
SVC=$(cl POST /services "{\"project_uuid\":\"$PROJ\",\"server_uuid\":\"$LOCALSRV\",\"environment_name\":\"production\",\"name\":\"dev\",\"docker_compose_raw\":\"$(sed "s|/home/nwn/dev|/home/$DEPLOY_USER/dev|g" templates/dev/dev.yaml | base64 -w0)\"}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["uuid"])'); echo $SVC
```

Success: an id.

### 3. The settings, then deploy

Ask the person for the live game's `NWNX_..._SKIP=n` lines and which of those plugins send things out (webhooks,
metrics); those stay off. Add the others to `PLUGINS` below as `"NWNX_X_SKIP":"n",` pairs.

```sh
umask 077; T=$(mktemp)
python3 - > $T <<EOF
import json, secrets
kv = {"NWNX_IMAGE": "nwnxee/unified:ed79330", "NWN_MODULE": "$MODULE_NAME", "NWN_SERVERNAME": "$MODULE_NAME (dev)",
      "NWN_PORT": "$DEV_PORT", "NWN_MAXCLIENTS": "8", "NWN_PLAYERPASSWORD": secrets.token_hex(6),
      "NWN_DMPASSWORD": secrets.token_hex(8), "NWN_ADMINPASSWORD": secrets.token_hex(8), "NWNX_SQL_PASSWORD": secrets.token_hex(12),
      "NWNX_SQL_SKIP": "n", "NWNX_SQL_TYPE": "mysql", "NWNX_SQL_DATABASE": "nwn", "NWNX_SQL_USERNAME": "nwn", "NWNX_UTIL_SKIP": "n"}
print(json.dumps({"data": [{"key": k, "value": v} for k, v in kv.items()]}))
EOF
cl PATCH /services/$SVC/envs/bulk "$(cat $T)" | python3 -c 'import json,sys; print("copied" if isinstance(json.load(sys.stdin), list) else "FAILED")'; rm -f $T
cl POST "/deploy?uuid=$SVC&force=false" > /dev/null; sleep 45
ssh $DEPLOY_USER@$CONTROL 'c=$(docker ps -aq --filter label=com.docker.compose.service=dev-nwserver); docker inspect -f "{{range .Config.Env}}{{println .}}{{end}}" $c | grep -E "^NWN_PUBLICSERVER=|^NWNX_SQL_HOST="; docker inspect -f "{{.State.Health.Status}}" $(docker ps -aq --filter label=com.docker.compose.service=dev-mariadb)'
```

Success: `copied`; `NWN_PUBLICSERVER=0`, `NWNX_SQL_HOST=dev-mariadb`, `healthy`. The dev game itself restarts until
step 5; that is expected. Tell the person the player password is in Coolify, on the service's settings page.

### 4. The firewall

**Ask first.** Tell the person: UDP `DEV_PORT` on the control host, from `BUILDERS` only, in the provider's
firewall; a person adds the rule (the chapter, step 4). Then, from the person's computer (one of `BUILDERS`) and
from the game host (not one of them):

```sh
templates/game/nwn-status.py $CONTROL $DEV_PORT
scp templates/game/nwn-status.py $DEPLOY_USER@$GAME:/tmp/ && ssh $DEPLOY_USER@$GAME "python3 /tmp/nwn-status.py $CONTROL $DEV_PORT"; echo "rc $?"
```

Before step 5 both say `no answer` (no module yet). Run them again after step 5. Success then: the first `is up:
module $MODULE_NAME`, the second `no answer from ...` and `rc 1`. If the second answers, the rule is too wide: stop and
ask.

### 5. A builder's key, and main's build

**Ask first** before adding a key to the control host. The builder makes the key on their own computer
(`ssh-keygen -t ed25519 -N '' -C dev-loader-NAME -f ~/.ssh/mymodule-dev`) and gives you the `.pub` file, here `PUB`.

```sh
{ printf 'command="/home/%s/dev/dev.sh \\"$SSH_ORIGINAL_COMMAND\\"",restrict ' $DEPLOY_USER; cat $PUB; } | ssh $DEPLOY_USER@$CONTROL 'cat >> ~/.ssh/authorized_keys'
lb() { CONTROL=$DEPLOY_USER@$CONTROL DEV_KEY=~/.ssh/mymodule-dev GH_REPO=$GH_REPO "$GUIDE/templates/dev/load-build.sh" "$@"; }
lb main | tail -1
ssh -i ~/.ssh/mymodule-dev -o IdentitiesOnly=yes $DEPLOY_USER@$CONTROL 'id' 2>&1 | tail -1
```

Success: `dev server is healthy with main-<7 characters>`, then `usage: load LABEL < module.mod | rollback | status
(got: id)`. Run step 4's two checks again now.

### 6. A pull request, and back

`lb` is the function from step 5.

```sh
lb pr $PR | tail -1
lb rollback | tail -1
lb status
```

Success: `dev server is healthy with pr-$PR-...`, then `... with main-... again`, then `loaded: ... main-...`,
`before it: ... pr-$PR-...`, `game: healthy`. If `load-build.sh` says there is no passing compile check, the pull
request's check failed or is older than 14 days: tell the person; do not re-run it yourself.

### 7. The scrub rules

Never write the rules yourself. List the live database's columns (names only, no values) for the person:

```sh
ssh $DEPLOY_USER@$GAME 'docker exec $(docker ps -q --filter label=com.docker.compose.service=mariadb) sh -c "mariadb -u\$MARIADB_USER -p\$MARIADB_PASSWORD \$MARIADB_DATABASE -N -e \"SELECT table_name, column_name, column_type FROM information_schema.columns WHERE table_schema = DATABASE() ORDER BY 1, 2\""'
```

**Stop and ask.** Show the list; the person decides which columns are private and writes `~/dev/scrub.list` on the
control host from `scrub.list.example` (the chapter, step 7). Then:

```sh
ssh $DEPLOY_USER@$CONTROL 'grep -cv -E "^(#|$)" ~/dev/scrub.list'
```

Success: a number (0 is right for a database with nothing private in it).

### 8. The dump key

**Ask first** before adding a key to the game host.

```sh
scp templates/dev/send-dump.sh $DEPLOY_USER@$GAME:game/ && ssh $DEPLOY_USER@$GAME 'chmod 755 game/send-dump.sh'
ssh $DEPLOY_USER@$CONTROL "ssh-keygen -q -t ed25519 -N '' -C dev-copy-db -f ~/.ssh/dev-copy-db && ssh-keyscan -t ed25519 $GAME_WG 2>/dev/null >> ~/.ssh/known_hosts && ssh-keygen -lf ~/.ssh/known_hosts | grep $GAME_WG | cut -d' ' -f2"
ssh $DEPLOY_USER@$GAME 'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub | cut -d" " -f2'
```

Success: the same `SHA256:...` twice. If they differ, stop and ask. Then:

```sh
ssh $DEPLOY_USER@$CONTROL 'cat ~/.ssh/dev-copy-db.pub' | { printf 'command="/home/%s/game/send-dump.sh",from="%s",restrict ' $DEPLOY_USER $CONTROL_WG; cat; } | ssh $DEPLOY_USER@$GAME 'cat >> ~/.ssh/authorized_keys'
ssh $DEPLOY_USER@$CONTROL "ssh -i ~/.ssh/dev-copy-db -o IdentitiesOnly=yes -o BatchMode=yes $DEPLOY_USER@$GAME_WG anything 2>&1 >/dev/null | head -1"
```

Success: `sending <backup> (N hours old)`.

### 9. The copy

**Ask first, every time.** Tell the person the dev database will be replaced and the dev game restarted, and wait for
a yes.

```sh
ssh $DEPLOY_USER@$CONTROL "cd dev && GAME=$DEPLOY_USER@$GAME_WG ./copy-db.sh --yes"; echo "exit $?"
```

Success: one line per rule ending `0 left`, `scrubbed with N rules ...`, `dev server is healthy on the copied
database`, `exit 0`. If it stops on a column that "looks private and has no rule", or a rule that names something
missing, show the person that line and stop and ask: the person adds or fixes the rule, never you.

## Verify

```sh
ssh $DEPLOY_USER@$CONTROL 'cd dev && ./dev.sh status'
ssh $DEPLOY_USER@$CONTROL 'cd dev && ./copy-db.sh --check'
curl -s https://api.nwn.beamdog.net/v1/servers | grep -c "$CONTROL"
ssh $DEPLOY_USER@$GAME 'docker inspect -f "{{.State.StartedAt}}" $(docker ps -q --filter label=com.docker.compose.service=nwserver)' | diff - /tmp/live-started.txt && echo "live game not restarted"
templates/game/nwn-status.py $GAME 5121
```

Success: `loaded: ... main-...` (or the pull request), `database: ... from live backup ...`, `game: healthy`; every
rule line ending `0 left` and `the dev database keeps every rule`; `0` (not in the public list); `live game not restarted`; the live game `is up`.

## Roll back

- **The dev server:** delete the `dev` service in Coolify (with its volumes: there are none; the data is in
  `~/dev`), then `sudo rm -rf ~/dev` on the control host if the person wants the data gone (the database's files belong to
  the database's own user, hence `sudo`). Nothing live reads any of it.
- **The keys:** on the control host, delete each `dev-loader-...` line from `~/.ssh/authorized_keys`, and
  `~/.ssh/dev-copy-db*`; on the game host, the `dev-copy-db` line from `~/.ssh/authorized_keys` and
  `game/send-dump.sh`.
- **The firewall:** a person removes the rule for `DEV_PORT`.
- A database copy cannot be undone on the dev server: what builders made there is gone. The live database is never
  changed by any step here.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- step 1, if the person hasn't said they want a dev server;
- the firewall (step 4), every key (steps 5 and 8), every database copy (step 9);
- writing or changing `scrub.list`, ever, and any copy that stops on a column or a rule;
- a host key fingerprint that doesn't match (step 8);
- the dev server answering from an address that isn't a builder's;
- a service called `nwserver` or `mariadb` on the control host, or a second `dev-` service anywhere;
- loading a pull request from outside the team (a fork whose author the person hasn't named);
- printing any password, the dump, or any value from the live database.
