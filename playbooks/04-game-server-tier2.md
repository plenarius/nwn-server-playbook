# Playbook 4, tier 2. The game in Coolify

For an agent. The chapter for people is [`chapters/04-game-server.md`](../chapters/04-game-server.md), section
"Tier 2". Follow the steps in order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `GAME` | The game host's public address | none: a person gives it |
| `CONTROL` | The control host's public address | none: a person gives it |
| `DEPLOY_USER` | The deploy user | `nwn` |

Secrets: `COOLIFY_TOKEN` (Root), placed by a person as in playbook 3. The game's settings, passwords included,
travel from `~/game/.env` on the game host into Coolify through a pipe and a private temporary file; never print
them, and never print an API response for the service or its variables. `~/game/db.env` is never read and never
sent to Coolify.

## Preconditions

```sh
ssh -f -N -L 8000:localhost:8000 $DEPLOY_USER@$CONTROL 2>/dev/null
cl() { curl -s -X "$1" -H @<(printf 'Authorization: Bearer %s\n' "$COOLIFY_TOKEN") -H 'Content-Type: application/json' ${3:+-d "$3"} "http://localhost:8000/api/v1$2"; }
GAMESRV=$(cl GET /servers | python3 -c 'import json,sys; print([s["uuid"] for s in json.load(sys.stdin) if s["ip"].startswith("10.")][0])'); echo $GAMESRV
ssh $DEPLOY_USER@$GAME 'cd game && docker compose ps --format "{{.Service}} {{.Health}}" | sort | tr "\n" " "; echo; ls .env db.env'
```

Success: an id; `mariadb healthy nwserver healthy`; `.env db.env`. Then `cl GET /services` must list no service
named `game`: if it does, stop and ask.

## Steps

### 1. The new scripts, and a fresh backup

```sh
scp templates/game/backup.sh templates/game/release.sh $DEPLOY_USER@$GAME:game/
ssh $DEPLOY_USER@$GAME 'cd game && sudo ./backup.sh | tail -1'
```

Success: `backup made: backups/...`.

### 2. The service, not started

```sh
PROJ=$(cl POST /projects '{"name":"game"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["uuid"])')
SVC=$(cl POST /services "{\"project_uuid\":\"$PROJ\",\"server_uuid\":\"$GAMESRV\",\"environment_name\":\"production\",\"name\":\"game\",\"docker_compose_raw\":\"$(sed "s|/home/nwn/game|/home/$DEPLOY_USER/game|g" templates/game/coolify.yaml | base64 -w0)\"}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["uuid"])'); echo $SVC
```

Success: an id.

### 3. The settings, copied without being shown

```sh
umask 077; T=$(mktemp)
ssh $DEPLOY_USER@$GAME 'cat game/.env' | python3 -c '
import json, sys
data = []
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line or line.lstrip().startswith("#") or "=" not in line: continue
    key, value = line.split("=", 1)
    if key == "COMPOSE_FILE" or key.startswith("MARIADB_ROOT"): continue
    data.append({"key": key, "value": value})
print(json.dumps({"data": data}))' > $T
cl PATCH /services/$SVC/envs/bulk "$(cat $T)" | python3 -c 'import json,sys; print("copied" if isinstance(json.load(sys.stdin), list) else "FAILED")'; rm -f $T
cl GET /services/$SVC/envs | python3 -c 'import json,sys; es=json.load(sys.stdin); print(len(es), "settings;", "no root password" if not any(e["key"].startswith("MARIADB_ROOT") for e in es) else "ROOT PASSWORD PRESENT")'
```

Success: `copied`, then a count and `no root password`.

### 4. The switch

**Ask first.** Tell the person the game will be away for about 20 seconds and players will be disconnected, and
wait for a yes.

```sh
ssh $DEPLOY_USER@$GAME 'cd game && docker compose stop nwserver mariadb 2>&1 | tail -1 && docker compose rm -f nwserver mariadb 2>&1 | tail -1'
cl POST "/deploy?uuid=$SVC&force=false" > /dev/null
for i in $(seq 60); do s=$(ssh $DEPLOY_USER@$GAME "docker inspect -f '{{.State.Health.Status}}' nwserver-$SVC 2>/dev/null"); [ "$s" = healthy ] && break; sleep 5; done; echo $s
```

Success: `healthy`. If it isn't healthy after five minutes, take the way back (Roll back) and report.

## Verify

```sh
templates/game/nwn-status.py $GAME
ssh $DEPLOY_USER@$GAME "docker inspect -f '{{.State.Health.Status}}' mariadb-$SVC; docker exec nwserver-$SVC env | grep -c ^MARIADB_ROOT; docker exec mariadb-$SVC env | grep -c ^MARIADB_ROOT"
ssh $DEPLOY_USER@$GAME 'cd game && sudo ./backup.sh | tail -1'
cl GET /services/$SVC | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status"))'
```

Success: the game answers with its module; `healthy`, `0`, `0`; a new backup; `running:healthy`.

## Roll back

The way back to tier 1, at any time:

```sh
SVC=$(cl GET /services | python3 -c 'import json,sys; r=[s["uuid"] for s in json.load(sys.stdin) if s["name"]=="game" and s.get("status","").startswith("running")]; print(r[0] if len(r)==1 else "")'); echo "service: ${SVC:-none or several}"
cl POST /services/$SVC/stop > /dev/null; sleep 30
ssh $DEPLOY_USER@$GAME '[ -z "$(docker ps -q --filter label=com.docker.compose.service=mariadb)" ] && cd game && docker compose up -d 2>&1 | tail -1 || echo "a game database is still running; not starting another"'
```

Never start tier 1's Compose while a game database container is still running: both would use the same folder.
MariaDB refuses to open files another copy has open, but don't rely on that.

Success: `docker compose ps` in `~/game` shows both healthy again. Settings changed in Coolify since the switch
must be copied into `~/game/.env` first; ask the person which.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- step 4, always;
- any restart or deploy of the game service afterwards;
- adding the database administrator's password to Coolify, ever;
- a setting in `~/game/.env` you don't recognise, or an empty password;
- stopping Coolify's proxy on the game host (it has no API; the chapter's step 19 says how).
