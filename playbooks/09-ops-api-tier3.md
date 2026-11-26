# Playbook 9, tier 3. Game data for a website

For an agent. The chapter for people is [`chapters/09-ops-api.md`](../chapters/09-ops-api.md), section "Tier 3".
Follow the steps in order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `CONTROL` | The control host's public address | none: a person gives it |
| `DEPLOY_USER` | The deploy user on the control host and the game host | `nwn` |
| `VAULT_FOLDER`, `VAULT_FILE` | One character for the check in Verify: a vault folder and a file in it, without `.bic` | none: a person gives them, or Verify skips the sheet |

Secrets: `COOLIFY_TOKEN` (Root), placed by a person as in playbook 3. The API's keys are in `~/ops-api/keys` on the
control host (playbook 9, tier 2, step 3); read them there, never print them. Never print a character sheet in
full: it holds a player's build. Report only the fields the checks name.

## Preconditions

```sh
ssh -f -N -L 8000:localhost:8000 $DEPLOY_USER@$CONTROL 2>/dev/null
cl() { curl -s -X "$1" -H @<(printf 'Authorization: Bearer %s\n' "$COOLIFY_TOKEN") -H 'Content-Type: application/json' ${3:+-d "$3"} "http://localhost:8000/api/v1$2"; }
OPS_SVC=$(cl GET /services | python3 -c 'import json,sys; r=[s["uuid"] for s in json.load(sys.stdin) if s["name"]=="ops-api"]; print(r[0] if len(r)==1 else "")'); echo "ops-api service: ${OPS_SVC:-none or several}"
ssh $DEPLOY_USER@$CONTROL "curl -s http://10.77.0.1:8100/health; echo; ssh -o BatchMode=yes $DEPLOY_USER@10.77.0.2 'grep -c ^NWN_MODULE= game/.env; ls game/home/hak | wc -l'; I=\$(docker inspect -f '{{.Config.Image}}' ops-api-$OPS_SVC); echo \$I; docker run --rm --entrypoint ls \$I app/gamedata >/dev/null 2>&1 && echo 'has game data' || echo 'no game data'"
```

Success: an id; `{"status":"ok"}`; `1`; a number of haks; the API's image; `has game data`. No service: playbook 9,
tier 2 first. SSH from the control host to the game host refused: the control host's own key is missing (playbook
7, tier 2, step 14 makes it); stop and ask. `no game data`: the API's image is older than its game data part; step 1.

## Steps

### 1. A version with the game data part

Skip if the precondition said `has game data`. Otherwise **ask first**: moving the API restarts it. After the yes, wait for no operations, then
build and switch:

```sh
ssh $DEPLOY_USER@$CONTROL 'curl -s -H @<(printf "Authorization: Bearer %s\n" "$(cat ~/ops-api/keys/admin)") http://10.77.0.1:8100/api/v1/server/progress | python3 -c "import json,sys; print(\"operations:\", len(json.load(sys.stdin)[\"operations\"]))"'
OPS_IMAGE=$(ssh $DEPLOY_USER@$CONTROL 'cd ~/nwn-ops-api && git pull -q && docker build -q -t nwn-ops-api:$(git rev-parse --short HEAD) . >/dev/null && echo nwn-ops-api:$(git rev-parse --short HEAD)'); echo $OPS_IMAGE
```

Success: `operations: 0`, then `nwn-ops-api:` and seven characters. Anything but 0: wait and look again; never go on
while operations run. Step 3 sets the image with the rest.

### 2. The API's copy of the game's files

```sh
scp -q templates/ops-api/gamedata-sync.sh templates/ops-api/gamedata-sync.service templates/ops-api/gamedata-sync.timer $DEPLOY_USER@$CONTROL:ops-api/
ssh $DEPLOY_USER@$CONTROL "chmod +x ~/ops-api/gamedata-sync.sh && mkdir -p ~/ops-api/gamedata && ~/ops-api/gamedata-sync.sh && sed -i 's|^User=nwn|User=$DEPLOY_USER|; s|/home/nwn/|/home/$DEPLOY_USER/|' ~/ops-api/gamedata-sync.service && sudo install -m 644 ~/ops-api/gamedata-sync.service ~/ops-api/gamedata-sync.timer /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now -q gamedata-sync.timer && systemctl is-active gamedata-sync.timer && ls ~/ops-api/gamedata"
```

Success: `base game data copied from the image ...` (or nothing about it, when it was copied before), a line
`module <name> (... changed), haks: ... changed, talk tables: ... changed`, `active`, and `hak module.mod nwn tlk`.
`no NWN_MODULE`: the game's `.env` has no module line; stop and ask.

### 3. Switch it on in the API

```sh
cl GET /services/$OPS_SVC | python3 -c 'import json,sys; print(json.load(sys.stdin)["docker_compose_raw"])' > /tmp/ops-api-compose.yaml
sed -i 's|^      # - /home/nwn/ops-api/gamedata:/data/game:ro|      - /home/nwn/ops-api/gamedata:/data/game:ro|; s|/home/nwn/|/home/'$DEPLOY_USER'/|g' /tmp/ops-api-compose.yaml
grep -c 'ops-api/gamedata:/data/game:ro' /tmp/ops-api-compose.yaml
cl PATCH /services/$OPS_SVC "{\"docker_compose_raw\":\"$(base64 -w0 /tmp/ops-api-compose.yaml)\"}" | python3 -c 'import json,sys; print("compose" if "uuid" in json.load(sys.stdin) else "FAILED")'; rm /tmp/ops-api-compose.yaml
cl PATCH /services/$OPS_SVC/envs/bulk '{"data":[{"key":"GAME_NWN_ROOT","value":"/data/game/nwn"},{"key":"GAME_MODULE_FILE","value":"/data/game/module.mod"},{"key":"GAME_HAK_DIR","value":"/data/game/hak"},{"key":"GAME_TLK_DIR","value":"/data/game/tlk"},{"key":"GAME_VAULT","value":"on"}]}' | python3 -c 'import json,sys; d=json.load(sys.stdin); print("copied", len(d) if isinstance(d, list) else "FAILED")'
[ -n "$OPS_IMAGE" ] && cl PATCH /services/$OPS_SVC/envs/bulk "{\"data\":[{\"key\":\"OPS_API_IMAGE\",\"value\":\"$OPS_IMAGE\"}]}" | python3 -c 'import json,sys; print("image", "set" if isinstance(json.load(sys.stdin), list) else "FAILED")'
```

Success: `1`, `compose`, `copied 5`, and `image set` if step 1 built one. `0` on the first line: the service's
compose file is older than this tier; stop and ask, and the person pastes the newer `coolify.yaml` in Coolify. Then **ask first**
(this restarts the API) and, after the yes:

```sh
cl POST /services/$OPS_SVC/restart > /dev/null; sleep 20
for i in $(seq 30); do s=$(ssh $DEPLOY_USER@$CONTROL "docker inspect -f '{{.State.Health.Status}}' ops-api-$OPS_SVC 2>/dev/null"); [ "$s" = healthy ] && break; sleep 5; done; echo $s
ssh $DEPLOY_USER@$CONTROL "docker logs ops-api-$OPS_SVC 2>&1 | grep -o 'configured: .*' | tail -1"
```

Success: `healthy`, and a `configured:` line that ends with `game_data, vault`.

### 4. The game data routes, and the refusals

```sh
ssh $DEPLOY_USER@$CONTROL 'A=http://10.77.0.1:8100/api/v1/game
k() { curl -s -o /dev/null -w "%{http_code} " -H @<(printf "Authorization: Bearer %s\n" "$(cat ~/ops-api/keys/$1)") "${@:2}"; }
k read $A/tlk/5; k read $A/2da/classes; k read "$A/2da/classes/7?names=true"; k read $A/items/nw_wswls001; k read $A/2da/no_such_table; k read -X POST $A/vault/x/y/retire; curl -s -o /dev/null -w "%{http_code}" $A/tlk/5; echo
curl -s -H @<(printf "Authorization: Bearer %s\n" "$(cat ~/ops-api/keys/read)") $A/tlk/5; echo'
```

Success: `200 200 200 200 404 403 401`, then `{"strref":5,"text":"Clerics"}` (in English; another language's
install says it in its own).

## Verify

```sh
ssh $DEPLOY_USER@$CONTROL "journalctl -u gamedata-sync.service --no-pager -n 1 -o cat; systemctl list-timers gamedata-sync.timer --no-pager | sed -n 2p | grep -c gamedata"
ssh $DEPLOY_USER@$CONTROL 'curl -s -H @<(printf "Authorization: Bearer %s\n" "$(cat ~/ops-api/keys/read)") http://10.77.0.1:8100/api/v1/game/2da/ex_notes 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get(\"from\", d.get(\"detail\")))"'
```

Success: a `module ... changed` line from the timer's last run, and `1`. The last line names the hak that holds
`ex_notes.2da` (chapter 7's example hak) or `No ex_notes.2da in the game data` if the person's haks don't have it:
both are fine; ask the person for one of their own 2DAs to try if they'd like a check that names their hak.

If the person gave `VAULT_FOLDER` and `VAULT_FILE`:

```sh
ssh $DEPLOY_USER@$CONTROL "curl -s -H @<(printf 'Authorization: Bearer %s\n' \"\$(cat ~/ops-api/keys/read)\") http://10.77.0.1:8100/api/v1/game/vault/$VAULT_FOLDER/$VAULT_FILE" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["level"], len(d["classes"]), "classes", len(d["equipped"]), "worn", "pack" in d or "gold" in d)'
```

Success: a level, a number of classes, a number of worn items, and `False`. Report nothing else from the sheet.

## Roll back

```sh
ssh $DEPLOY_USER@$CONTROL 'sudo systemctl disable --now -q gamedata-sync.timer && sudo rm /etc/systemd/system/gamedata-sync.service /etc/systemd/system/gamedata-sync.timer && sudo systemctl daemon-reload && echo timer removed'
for k in GAME_NWN_ROOT GAME_MODULE_FILE GAME_HAK_DIR GAME_TLK_DIR GAME_VAULT; do u=$(cl GET /services/$OPS_SVC/envs | python3 -c "import json,sys; r=[e['uuid'] for e in json.load(sys.stdin) if e['key']=='$k']; print(r[0] if r else '')"); [ -n "$u" ] && cl DELETE /services/$OPS_SVC/envs/$u > /dev/null; done; echo settings removed
```

Then **ask first**, and restart the API as in step 3; its `configured:` line no longer has `game_data`. The folder
`~/ops-api/gamedata` and the mount line can stay; the vault routes go off with `GAME_VAULT`, and the `configured:` line no longer has `vault`.
A newer image from step 1 can stay too, or go back to the old tag the same way as step 16 of the chapter.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- every restart of the API (steps 1 and 3, and Roll back), and never while `progress` shows operations;
- retiring any character, even as a dry run on a server people play on: the person says which, and why;
- giving the read key to anything that would show character sheets as they come, without a list of who agreed;
- printing a character sheet, a vault folder's listing or a player's CD key into a message, a file or a log;
- SSH from the control host to the game host refused, or a game host without `NWN_MODULE` in `game/.env`.
