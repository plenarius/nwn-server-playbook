# Playbook 9, tier 2. The operations API

For an agent. The chapter for people is [`chapters/09-ops-api.md`](../chapters/09-ops-api.md). Follow the steps in
order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `GAME` | The game host's public address | none: a person gives it |
| `CONTROL` | The control host's public address | none: a person gives it |
| `DEPLOY_USER` | The deploy user on both | `nwn` |
| `GAME_SVC` | The game's Coolify service id (chapter 4, tier 2) | none: from Preconditions |
| `NWNX_TAG` | The moving NWNX tag the game and the API share | `nwnxee/unified:build8193.37.17` |
| `REPO_URL` | nwn-ops-api's repository | `https://github.com/plenarius/nwn-ops-api.git` |

Secrets, never printed and never in your prompt:

- `COOLIFY_TOKEN`: your Root token for Coolify's API, placed by a person as in playbook 3.
- The API's own Coolify token: a person makes it in the dashboard with **read**, **write** and **deploy** only
  (chapter, step 6) and puts it in `~/ops-api/keys/coolify` on the control host (`umask 077`).
- The four API keys: step 3 makes them on the control host in `~/ops-api/keys/{full,admin,team,read}`. Tell the person
  to copy them into their password manager; never read them out.

All calls to the API run on the control host and read their key from those files.

## Preconditions

```sh
ssh -f -N -L 8000:localhost:8000 $DEPLOY_USER@$CONTROL 2>/dev/null
cl() { curl -s -X "$1" -H @<(printf 'Authorization: Bearer %s\n' "$COOLIFY_TOKEN") -H 'Content-Type: application/json' ${3:+-d "$3"} "http://localhost:8000/api/v1$2"; }
GAME_SVC=$(cl GET /services | python3 -c 'import json,sys; r=[s["uuid"] for s in json.load(sys.stdin) if s["name"]=="game"]; print(r[0] if len(r)==1 else "")'); echo "game service: ${GAME_SVC:-none or several}"
cl GET /services | python3 -c 'import json,sys; print("ops-api service exists" if any(s["name"]=="ops-api" for s in json.load(sys.stdin)) else "no ops-api service")'
ssh $DEPLOY_USER@$CONTROL 'ping -c1 -W2 10.77.0.2 >/dev/null && echo tunnel up; test -s ~/ops-api/keys/coolify && echo coolify token placed; sudo -n true && echo sudo'
ssh $DEPLOY_USER@$GAME "docker inspect -f '{{.State.Health.Status}} {{.Config.Image}}' nwserver-$GAME_SVC; sudo -n true && echo sudo"
```

Success: an id; `no ops-api service`; `tunnel up`, `coolify token placed`, `sudo`; `healthy` with the game's image,
and `sudo`. If the token isn't placed, stop and ask for it. If the game's image isn't `$NWNX_TAG`, step 7 asks.

## Steps

### 1. Staging folders on the game host

```sh
ssh $DEPLOY_USER@$GAME "sudo install -d -o $DEPLOY_USER -g $DEPLOY_USER ~/game/home/modules/.staged ~/game/home/hak/.staged && stat -c '%U %n' ~/game/home/modules/.staged ~/game/home/hak/.staged"
```

Success: two lines starting with the deploy user's name.

### 2. The image

```sh
ssh $DEPLOY_USER@$CONTROL "test -d ~/nwn-ops-api || git clone -q $REPO_URL ~/nwn-ops-api; cd ~/nwn-ops-api && git pull -q && docker build -q -t nwn-ops-api:\$(git rev-parse --short HEAD) . >/dev/null && echo nwn-ops-api:\$(git rev-parse --short HEAD)"
```

Success: one line, `nwn-ops-api:` and seven characters. Note it as `OPS_IMAGE`.

### 3. Keys

```sh
ssh $DEPLOY_USER@$CONTROL 'umask 077; mkdir -p ~/ops-api/keys ~/ops-api/ssh && for k in full admin team read; do test -s ~/ops-api/keys/$k || openssl rand -hex 32 > ~/ops-api/keys/$k; done
  test -s ~/ops-api/ssh/id_ed25519 || ssh-keygen -q -t ed25519 -N "" -C nwn-ops-api -f ~/ops-api/ssh/id_ed25519
  ssh-keyscan -q -t ed25519 10.77.0.2 > ~/ops-api/ssh/known_hosts; chmod 644 ~/ops-api/ssh/known_hosts; wc -c ~/ops-api/keys/full ~/ops-api/keys/admin ~/ops-api/keys/team ~/ops-api/keys/read | head -4; id -u'
ssh $DEPLOY_USER@$CONTROL 'cat ~/ops-api/ssh/id_ed25519.pub' | ssh $DEPLOY_USER@$GAME 'k=$(cat); grep -qxF "$k" ~/.ssh/authorized_keys || echo "$k" >> ~/.ssh/authorized_keys; grep -c nwn-ops-api ~/.ssh/authorized_keys'
ssh $DEPLOY_USER@$CONTROL "ssh -i ~/ops-api/ssh/id_ed25519 -o UserKnownHostsFile=~/ops-api/ssh/known_hosts -o BatchMode=yes $DEPLOY_USER@10.77.0.2 'docker ps -q --filter name=nwserver | wc -l'"
```

Success: four files of `65` bytes; `1000`; `1`; `1`. If `id -u` isn't `1000`, run
`sudo chown 1000 ~/ops-api/ssh/id_ed25519 ~/ops-api/ssh/known_hosts` on the control host. Tell the person the four
keys are in `~/ops-api/keys` on the control host, to copy into their password manager.

### 4. The service, with its settings

```sh
LOCAL=$(cl GET /servers | python3 -c 'import json,sys; print([s["uuid"] for s in json.load(sys.stdin) if not s["ip"].startswith("10.")][0])')
PROJ=$(cl POST /projects '{"name":"ops-api"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["uuid"])')
OPS_SVC=$(cl POST /services "{\"project_uuid\":\"$PROJ\",\"server_uuid\":\"$LOCAL\",\"environment_name\":\"production\",\"name\":\"ops-api\",\"docker_compose_raw\":\"$(sed "s|/home/nwn/|/home/$DEPLOY_USER/|g" templates/ops-api/coolify.yaml | base64 -w0)\"}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["uuid"])'); echo $OPS_SVC
umask 077; T=$(mktemp)
ssh $DEPLOY_USER@$CONTROL "cd ~/ops-api/keys && python3 -c '
import json, sys
r = lambda f: open(f).read().strip()
env = {\"OPS_API_IMAGE\": \"$OPS_IMAGE\", \"OPS_API_BIND\": \"10.77.0.1\",
       \"OPS_API_KEY\": r(\"full\"), \"OPS_API_ADMIN_KEY\": r(\"admin\"), \"OPS_API_TEAM_KEY\": r(\"team\"), \"OPS_API_READ_KEY\": r(\"read\"),
       \"GAME_HOST\": \"10.77.0.2\", \"SSH_USER\": \"$DEPLOY_USER\", \"SSH_SUDO\": \"true\", \"GAME_DIR\": \"/home/$DEPLOY_USER/game\",
       \"COOLIFY_ENV_FILE\": \"/data/coolify/services/$GAME_SVC/.env\", \"DEPLOY_HOOK\": \"/home/$DEPLOY_USER/game/backup.sh\",
       \"COOLIFY_API_URL\": \"http://10.77.0.1:8000\", \"COOLIFY_TOKEN\": r(\"coolify\"), \"COOLIFY_SERVICE_UUID\": \"$GAME_SVC\",
       \"NWNX_IMAGE\": \"$NWNX_TAG\"}
print(json.dumps({\"data\": [{\"key\": k, \"value\": v} for k, v in env.items()]}))'" > $T
cl PATCH /services/$OPS_SVC/envs/bulk "$(cat $T)" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("copied", len(d) if isinstance(d, list) else "FAILED")'; rm -f $T
cl POST "/deploy?uuid=$OPS_SVC&force=false" > /dev/null
for i in $(seq 30); do s=$(ssh $DEPLOY_USER@$CONTROL "docker inspect -f '{{.State.Health.Status}}' ops-api-$OPS_SVC 2>/dev/null"); [ "$s" = healthy ] && break; sleep 5; done; echo $s
```

Success: an id, `copied 16`, `healthy`. Never print `$T` or any answer about the service's variables.

### 5. Reachable only where it should be

```sh
ssh $DEPLOY_USER@$CONTROL "curl -s http://10.77.0.1:8100/health; echo; curl -s -m3 http://127.0.0.1:8100/health || echo refused locally; docker logs ops-api-$OPS_SVC 2>&1 | grep -o 'configured: .*'"
curl -s -m 5 http://$CONTROL:8100/health || echo "closed from outside"
```

Success: `{"status":"ok"}`, `refused locally`, `configured: game, deploy, haks, logs, coolify`, `closed from outside`.

### 6. Every read route, and the refusals

```sh
ssh $DEPLOY_USER@$CONTROL 'A=http://10.77.0.1:8100/api/v1
k() { curl -s -o /dev/null -w "%{http_code} " -H @<(printf "Authorization: Bearer %s\n" "$(cat ~/ops-api/keys/$1)") "${@:2}"; }
for p in server/status server/modules "server/logs?lines=3" server/progress; do k team $A/$p; done; k admin $A/meta/systems
k team -X POST -H "Content-Type: application/json" -d "{}" $A/server/stop; k read $A/server/status; k read "$A/server/logs?lines=3"; k read -X POST -H "Content-Type: application/json" -d "{}" $A/server/restart; curl -s -o /dev/null -w "%{http_code} " -H "Authorization: Bearer wrong" $A/server/status; k admin $A/server/repos; echo'
```

Success: `200 200 200 200 200 403 200 403 403 401 503`.

### 7. The NWNX tag

If the precondition showed the game on `$NWNX_TAG`, skip this step. Otherwise **ask first**: tell the person the
game moves to the moving tag (chapter, step 13), which restarts it, and wait for a yes. Then:

```sh
ID=$(cl GET /services/$GAME_SVC/envs | python3 -c 'import json,sys; print([e["uuid"] for e in json.load(sys.stdin) if e["key"]=="NWNX_IMAGE"][0])')
cl PATCH /services/$GAME_SVC/envs "{\"uuid\":\"$ID\",\"key\":\"NWNX_IMAGE\",\"value\":\"$NWNX_TAG\"}" > /dev/null
ssh $DEPLOY_USER@$GAME "sed -i 's|^NWNX_IMAGE=.*|NWNX_IMAGE=$NWNX_TAG|' ~/game/.env && grep ^NWNX_IMAGE ~/game/.env"
cl POST /services/$GAME_SVC/restart > /dev/null; sleep 20
for i in $(seq 40); do s=$(ssh $DEPLOY_USER@$GAME "docker inspect -f '{{.Config.Image}} {{.State.Health.Status}}' nwserver-$GAME_SVC"); [ "$s" = "$NWNX_TAG healthy" ] && break; sleep 5; done; echo $s
```

Success: the `NWNX_IMAGE` line, then `$NWNX_TAG healthy`.

## Verify

Restarts disconnect players: **ask first** whether anyone is on and whether a restart now is fine.

```sh
ssh $DEPLOY_USER@$CONTROL 'A=http://10.77.0.1:8100/api/v1
k() { curl -s -H @<(printf "Authorization: Bearer %s\n" "$(cat ~/ops-api/keys/$1)") -H "Content-Type: application/json" "${@:2}"; echo; }
k team -X POST -d "{\"wait_minutes\": 1, \"reason\": \"checking the ops API\"}" $A/server/restart
sleep 5; k team -X POST $A/server/cancel-restart
k team $A/server/status | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[\"status\"], d[\"module\"], d[\"nwnx_running\"], d[\"nwnx_latest\"])"'
```

Success: `"ok":true` with `Restart countdown started (60s)`, then `"ok":true` with `Restart cancelled`, then
`running:healthy`, the module, and two builds (the same one twice when the game is up to date). Nothing restarted.

## Roll back

```sh
OPS_SVC=$(cl GET /services | python3 -c 'import json,sys; r=[s["uuid"] for s in json.load(sys.stdin) if s["name"]=="ops-api"]; print(r[0] if len(r)==1 else "")'); echo "service: ${OPS_SVC:-none or several}"
cl DELETE "/services/$OPS_SVC?delete_volumes=false"; echo; sleep 15
PROJ=$(cl GET /projects | python3 -c 'import json,sys; r=[p["uuid"] for p in json.load(sys.stdin) if p["name"]=="ops-api"]; print(r[0] if len(r)==1 else "")'); cl DELETE /projects/$PROJ; echo
ssh $DEPLOY_USER@$CONTROL 'docker ps -a --format "{{.Names}}" | grep ops-api || echo "no ops-api container"'
ssh $DEPLOY_USER@$GAME "sed -i '/ nwn-ops-api\$/d' ~/.ssh/authorized_keys; grep -c nwn-ops-api ~/.ssh/authorized_keys"
```

If the first line says `none or several`, stop and ask. Success: `Service deletion request queued.`,
`Project deleted.`, `no ops-api container`, `0`. The game keeps running throughout; the staging folders, the image and
`~/ops-api` on the control host can stay. Step 7 can't be undone by this: going back to a commit tag is the same
change with the old tag, and a restart, which the person says yes to.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- step 7, and the restart in Verify;
- any restart, stop, deploy, full deploy, NWNX update or release on a server people play on, ever;
- moving the API to a new image while `server/progress` shows operations running (never: wait for them);
- a missing token, or a token with Root where read, write and deploy would do;
- publishing the API, Redis or Coolify on a public address, or opening 8100 or 6379 at a provider firewall;
- putting a password on Redis for the game (it breaks the subscription: chapter, step 10);
- `REPOS`, `GITHUB_TOKEN` or `DISCORD_WEBHOOK_URL`: the person makes the token and the webhook and says which
  repositories and channel.
