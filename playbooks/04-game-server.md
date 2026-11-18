# Playbook 4. Run the game server with NWNX (tier 1)

For an agent. The chapter for people is [`chapters/04-game-server.md`](../chapters/04-game-server.md). Follow the
steps in order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer, unless it starts with `ssh`.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `SERVER` | The server's address or name, from playbooks 1 and 2 | none: a person gives it |
| `DEPLOY_USER` | The account made in playbook 1 | `nwn` |
| `NWNX_BUILD` | The build tag of `nwnxee/unified` for the players' game | `build8193.37.17` |
| `NWN_SERVERNAME` | The name players see. No `\|` or `&` in it | none: a person gives it |
| `NWN_MAXCLIENTS` | The player limit | `16` |
| `NWN_PORT` | The game's UDP port, the one opened in playbook 1 | `5121` |

Secrets: the DM, admin and player passwords. They live only in `~/game/.env` on the server. A person types them
there, or step 3 makes them on the server without showing them. Never print them, and never run a command whose
output contains them. These three do: `cat .env`, `docker compose config`, and `docker inspect` of the container
without a `-f` format. The server's logs do not contain them.

## Preconditions

Playbook 1 is done, and nothing is installed yet:

```sh
ssh $DEPLOY_USER@$SERVER 'docker info --format "{{.LiveRestoreEnabled}}"; sudo ufw status | grep -c "'$NWN_PORT'/udp"; ls -d ~/game 2>/dev/null | wc -l; docker ps -aq | wc -l'
```

Success: `true`, `2`, `0`, `0`. If `~/game` exists or any container exists, this machine already runs something:
stop and ask.

## Steps

### 1. Find the commit tag for the build

```sh
TAG=$(ssh $DEPLOY_USER@$SERVER 'docker pull -q nwnxee/unified:'$NWNX_BUILD' >/dev/null && docker image inspect nwnxee/unified:'$NWNX_BUILD' -f "{{index .Config.Labels \"org.opencontainers.image.revision\"}}" | cut -c1-7')
echo $TAG
```

Success: seven letters and digits (on the test: `ed79330`). The pull is about 260 MB.

### 2. Copy the files

```sh
scp -r templates/game $DEPLOY_USER@$SERVER:game
```

Success: exit status 0.

### 3. Write the settings

```sh
ssh $DEPLOY_USER@$SERVER "cd game && { [ -e .env ] || cp .env.example .env; } && chmod 600 .env && sed -i 's|^NWNX_IMAGE=.*|NWNX_IMAGE=nwnxee/unified:$TAG|; s|^NWN_SERVERNAME=.*|NWN_SERVERNAME=$NWN_SERVERNAME|; s|^NWN_MAXCLIENTS=.*|NWN_MAXCLIENTS=$NWN_MAXCLIENTS|; s|^NWN_PORT=.*|NWN_PORT=$NWN_PORT|' .env && grep -c '^NWNX_IMAGE=nwnxee/unified:$TAG\$' .env"
```

Success: `1`.

Then the passwords. Ask the person whether they have put their own in `~/game/.env`. If they would rather have
them made, this fills only the ones still empty and shows none:

```sh
ssh $DEPLOY_USER@$SERVER 'cd game && for v in NWN_DMPASSWORD NWN_ADMINPASSWORD; do grep -q "^$v=." .env || sed -i "s|^$v=.*|$v=$(openssl rand -hex 8)|" .env; done; grep -c "^NWN_\(DM\|ADMIN\)PASSWORD=." .env; stat -c %a .env'
```

Success: `2` and `600`. Tell the person the passwords are in `~/game/.env` on the server, for them to read.

### 4. Start the server and wait for healthy

```sh
ssh $DEPLOY_USER@$SERVER 'cd game && docker compose up -d && for i in $(seq 60); do s=$(docker inspect -f "{{.State.Health.Status}}" game-nwserver-1); [ "$s" = healthy ] && break; sleep 2; done; echo $s'
```

Success: the last line is `healthy`. It took 7 seconds on the test. If it is not healthy after two minutes, read
`docker compose logs --tail 50` on the server and stop and ask.

### 5. Ask it from outside

```sh
templates/game/nwn-status.py $SERVER $NWN_PORT
```

Success: `... is up: module DockerDemo, room for $NWN_MAXCLIENTS players`, exit status 0.

## Verify

```sh
ssh $DEPLOY_USER@$SERVER 'docker inspect game-nwserver-1 -f "{{index .Config.Labels \"org.opencontainers.image.revision\"}} {{.HostConfig.RestartPolicy.Name}} {{.HostConfig.LogConfig.Config}} {{.State.Health.Status}}" | cut -c1-7,41-'
```

Success: `$TAG unless-stopped map[max-file:3 max-size:10m] healthy`.

```sh
ssh $DEPLOY_USER@$SERVER 'cd game && docker compose logs | grep -c "Loaded plugin"; sudo ls home | wc -l; sudo ls logs'
```

Success: `3` (Core, ServerLogRedirector and Util), `12`, and a list with `nwserverLog1.txt` in it.

```sh
templates/game/nwn-status.py $SERVER $NWN_PORT
```

Success: as in step 5. Run this one from a machine that is not the server.

The person does the last check: they join with the game (Direct Connect to `$SERVER:$NWN_PORT`). You cannot do
this one for them.

## Roll back

- **Stop the server and keep everything:** `ssh $DEPLOY_USER@$SERVER 'cd game && docker compose down'`. The
  folders `home` and `logs` stay, and `docker compose up -d` brings the same server back.
- **Go back to an earlier version:** put the earlier tag in the `NWNX_IMAGE` line of `.env`, then
  `docker compose up -d`.
- **Remove it all:** a person deletes `~/game` (its files belong to root). On a server that players have used, that
  folder holds their characters. Do not delete it yourself.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- stopping, restarting or running `docker compose up -d` on a server that may have players on it;
- changing the `NWNX_IMAGE` line on a server that is in use;
- setting `NWN_PUBLICSERVER=1`: it puts the server in the public list;
- deleting anything under `~/game/home`;
- any command whose output would show `.env` or a password;
- a server that is not healthy two minutes after it started.
