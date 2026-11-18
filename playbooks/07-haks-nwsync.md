# Playbook 7. Custom content and NWSync (tier 1)

For an agent. The chapter for people is [`chapters/07-haks-nwsync.md`](../chapters/07-haks-nwsync.md). Follow the
steps in order. Do not go on from a step whose check fails.

`GUIDE` below is the root of this repository on the person's computer.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `GUIDE` | Where this repository is | none: a person gives it |
| `HAKS_DIR` | The folder to create for the content repository | `~/myhaks` |
| `REPO_DIR` | The module's repository, from playbook 6 | `~/mymodule` |
| `MODULE_NAME` | The built module's name, from playbook 6 | `mymodule` |
| `TLK` | The talk table's name, without `.tlk` | `my_tlk` |
| `HAKS` | The haks the module uses, in order, the winning one first, without `.hak` | `my_first_hak` |
| `SERVER` | The server's address or name | none: a person gives it |
| `DEPLOY_USER` | The account made in playbook 1 | `nwn` |
| `NWSYNC_HOST` | The name players download from, such as `nwsync.example.org` | none: a person gives it |

Secrets: none pass through you. The certificate is requested by the web server itself.

## Preconditions

The tools are there, playbook 6 is done, and the content repository does not exist yet:

```sh
command -v nwn_erf nwn_tlk nwn_nwsync_write >/dev/null && echo "tools ok"; ls "$REPO_DIR/src/ifo/module.ifo.json" >/dev/null && echo "module ok"; ls -d "$HAKS_DIR" 2>/dev/null | wc -l
ssh $DEPLOY_USER@$SERVER 'cd game && docker compose ps --format "{{.Service}} {{.Health}}"; grep -c "^NWN_NWSYNCURL=" .env'
```

Success: `tools ok`, `module ok`, `0`, then `mariadb healthy`, `nwserver healthy` and `0`.

`NWSYNC_HOST` must already point at the server. A person makes that record, or you make it with playbook 2 after
their yes. Check it at the source, never at a resolver first:

```sh
NS=$(dig +short NS ${NWSYNC_HOST#*.} | head -1); dig +short $NWSYNC_HOST @$NS | tail -1
```

Success: the server's address.

The provider's firewall must allow TCP 80 and 443 inbound. A person does that. Ask them to confirm it.

## Steps

### 1. Start the content repository and build

```sh
cp -r "$GUIDE/templates/haks" "$HAKS_DIR" && cd "$HAKS_DIR" && git init -q -b main && ./build.sh 2>&1 | grep -E "^(packed|built)"
```

Success: one `packed` line per folder in `haks/` and one `built` line per talk table. With a person's own content,
they put it in place before this step; you do not choose or fetch content.

### 2. Tell the module, and build it

```sh
cd "$REPO_DIR" && cp "$GUIDE/templates/module/tools/set_haks.py" tools/ && python3 tools/set_haks.py --tlk $TLK $HAKS && nasher pack --yes | tail -1 && python3 tools/check_compiled.py $MODULE_NAME.mod src
```

Success: a line naming the number of haks and the talk table, `Success: packed $MODULE_NAME.mod`, and the check's
one-line summary. Commit the change on a branch and open a pull request, as playbook 6 says.

### 3. Write the download folder

```sh
cd "$HAKS_DIR" && mkdir -p build/nwsync && nwn_nwsync_write --description="$MODULE_NAME content" --path build/hak --path build/tlk build/nwsync "$REPO_DIR/$MODULE_NAME.mod" >/dev/null 2>&1; HASH=$(cat build/nwsync/latest); echo $HASH; ls build/nwsync/manifests/$HASH >/dev/null && echo "manifest ok"
```

Success: 40 letters and digits, then `manifest ok`.

### 4. Open the host firewall for the web

```sh
ssh $DEPLOY_USER@$SERVER 'cd ~/host && sudo ALLOW_WEB=1 STEPS=firewall ./prepare-host.sh | tail -1; sudo ufw status | grep -c -E "^(80|443)/tcp"'
```

Success: `== done: firewall` and `4` (two ports, each for IPv4 and IPv6).

### 5. Send the web files, the download folder and the content

```sh
scp "$GUIDE/templates/game/compose.web.yaml" "$GUIDE/templates/game/Caddyfile" "$GUIDE/templates/game/.env.web.example" $DEPLOY_USER@$SERVER:game/
rsync -a "$HAKS_DIR/build/nwsync/" $DEPLOY_USER@$SERVER:game/nwsync/
scp "$HAKS_DIR"/build/hak/*.hak "$HAKS_DIR"/build/tlk/*.tlk "$REPO_DIR/$MODULE_NAME.mod" $DEPLOY_USER@$SERVER:
```

Success: exit status 0 for each.

### 6. Write the settings

```sh
ssh $DEPLOY_USER@$SERVER "cd game && sed -i '/^COMPOSE_FILE=/d' .env && cat .env.web.example >> .env && sed -i 's|^NWSYNC_HOST=.*|NWSYNC_HOST=$NWSYNC_HOST|; s|^NWN_NWSYNCURL=.*|NWN_NWSYNCURL=https://$NWSYNC_HOST|' .env && grep -c '^COMPOSE_FILE=compose.yaml:compose.db.yaml:compose.web.yaml\$' .env"
```

Success: `1`.

### 7. Replace the content and start everything

**Ask first if players may be on the server.** This stops the game for a short while.

```sh
ssh $DEPLOY_USER@$SERVER 'cd game && docker compose stop nwserver && sudo cp ~/*.hak home/hak/ && sudo cp ~/*.tlk home/tlk/ && sudo cp ~/*.mod home/modules/ && docker compose up -d && for i in $(seq 90); do s=$(docker inspect -f "{{.State.Health.Status}}" game-nwserver-1); [ "$s" = healthy ] && break; sleep 2; done; docker compose ps --format "{{.Service}} {{.State}}"'
```

Success: `caddy running`, `mariadb running`, `nwserver running`.

## Verify

The download address answers with the content just written. Give the certificate up to two minutes on a first
start.

```sh
curl -s -m 10 https://$NWSYNC_HOST/latest; echo; curl -s -m 10 https://$NWSYNC_HOST/manifests/$HASH | sha1sum | cut -c1-40
```

Success: `$HASH` twice.

The game advertises it:

```sh
ssh $DEPLOY_USER@$SERVER 'cd game && docker compose logs nwserver | grep -a "now advertising" | tail -1 | grep -o "[0-9a-f]\{40\}"'
```

Success: `$HASH`. Lines saying `Failure to get latest manifest hash` before it are normal on a first start: the
game asked before the certificate existed, and asked again.

```sh
"$GUIDE/templates/game/nwn-status.py" $SERVER
```

Success: the game answers, with `module $MODULE_NAME`.

The person does the last check: they join with the game and see it download the content.

## Later updates

Always in this order, so the server never asks players for content that is not there yet:

1. Build (steps 1 and 2 without the copying and `git init`).
2. Step 3, then only the `rsync` line of step 5. This adds files and changes nothing for a running game.
3. The last line of step 5, then step 7.

## Roll back

- **Back to the content before an update:** the earlier haks, talk table and module must be copied back into
  `home/hak`, `home/tlk` and `home/modules` (keep the previous build until the new one has been played on), then
  restart the game. Write the download folder again from that earlier build so `latest` names it.
- **Take NWSync away again:** remove the lines that step 6 added to `.env`, put back
  `COMPOSE_FILE=compose.yaml:compose.db.yaml`, and run `docker compose up -d --remove-orphans`.
- **Cannot be undone:** the certificate's name is in public certificate logs from the moment it is issued.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- making or changing a DNS record, or asking for a certificate for a name the person has not approved;
- step 7, or any restart, on a server that may have players on it;
- deleting anything from `game/nwsync` on the server. Old content there may still be what a running game
  advertises;
- choosing, downloading or adding content yourself. What goes into a hak is the person's decision, and so is
  whether its terms allow sharing it;
- a download address that still has no certificate after two minutes: read `docker compose logs caddy` and report.
