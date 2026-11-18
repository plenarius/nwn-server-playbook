# Playbook 11. A one-page website (tier 1)

For an agent. The chapter for people is [`chapters/11-website.md`](../chapters/11-website.md). Follow the steps in
order. Do not go on from a step whose check fails.

`GUIDE` below is the root of this repository on the person's computer.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `GUIDE` | Where this repository is | none: a person gives it |
| `SITE_DIR` | The folder with the person's page | `~/mysite` |
| `SITE_HOST` | The website's name, such as `www.example.org` | none: a person gives it |
| `SERVER` | The server's address or name | none: a person gives it |
| `DEPLOY_USER` | The account made in playbook 1 | `nwn` |

Secrets: none. The certificate is requested by the web server itself.

The words on the page belong to the person. You may create `SITE_DIR` from the template when it does not exist,
and you publish what is there. You do not write or change what the page says about their world unless they ask
you to, and you never put a password on it.

## Preconditions

```sh
ls "$SITE_DIR/index.html" 2>/dev/null || echo "no page yet"
grep -c -E "example\.org|My World" "$SITE_DIR/index.html" 2>/dev/null
ssh $DEPLOY_USER@$SERVER 'cd game && docker compose ps --format "{{.Service}} {{.State}}" | grep -c "nwserver running"; grep -c "^SITE_HOST=" .env; grep -c "compose.web.yaml" .env'
```

Success: the page's path, then `0` (no placeholder text is left), then `1`, `0` and either `1` (the web server
from playbook 7 is there) or `0` (it is not; do step 2).

If there is no page yet, create it with `cp -r "$GUIDE/templates/site" "$SITE_DIR"` and hand back to the person:
they fill it in. If placeholder text is left, tell them which lines and wait.

`SITE_HOST` must already point at the server. A person makes that record, or you make it with playbook 2 after
their yes. Check it at the source, never at a resolver first:

```sh
NS=$(dig +short NS ${SITE_HOST#*.} | head -1); dig +short $SITE_HOST @$NS | tail -1
```

Success: the server's address.

## Steps

### 1. Send the page

```sh
ssh $DEPLOY_USER@$SERVER 'mkdir -p game/sites game/site && sudo chown '$DEPLOY_USER': game/site'
rsync -a --delete --exclude .git "$SITE_DIR/" $DEPLOY_USER@$SERVER:game/site/ && ssh $DEPLOY_USER@$SERVER 'ls game/site | grep -c "^index.html$"; ls -a game/site | grep -c "^\.git$"'
```

Success: `1` and `0`.

### 2. Only if the web server is not there yet

The provider's firewall must allow TCP 80 and 443 inbound. A person does that. Ask them to confirm it. Then:

```sh
ssh $DEPLOY_USER@$SERVER 'cd ~/host && sudo ALLOW_WEB=1 STEPS=firewall ./prepare-host.sh | tail -1'
scp "$GUIDE/templates/game/compose.web.yaml" "$GUIDE/templates/game/Caddyfile" $DEPLOY_USER@$SERVER:game/
ssh $DEPLOY_USER@$SERVER 'cd game && if grep -q "^COMPOSE_FILE=" .env; then sed -i "s|^COMPOSE_FILE=\(.*\)$|COMPOSE_FILE=\1:compose.web.yaml|" .env; else echo "COMPOSE_FILE=compose.yaml:compose.web.yaml" >> .env; fi; grep -c "^COMPOSE_FILE=.*compose.web.yaml$" .env'
```

Success: `== done: firewall`, then `1`.

### 3. Switch the site on

```sh
scp "$GUIDE/templates/game/sites/www.caddy" $DEPLOY_USER@$SERVER:game/sites/
scp "$GUIDE/templates/game/.env.site.example" $DEPLOY_USER@$SERVER:game/
ssh $DEPLOY_USER@$SERVER "cd game && cat .env.site.example >> .env && sed -i 's|^SITE_HOST=.*|SITE_HOST=$SITE_HOST|' .env && before=\$(docker inspect -f '{{.Id}}' game-nwserver-1) && docker compose up -d caddy 2>&1 | tail -1 && [ \"\$before\" = \"\$(docker inspect -f '{{.Id}}' game-nwserver-1)\" ] && echo 'game untouched'"
```

Success: a line saying the `caddy` container started, then `game untouched`. This command restarts only the web
server, so it needs no quiet hour.

## Verify

Give the certificate up to two minutes on a first start.

```sh
curl -s -m 10 -o /dev/null -w '%{http_code}\n' https://$SITE_HOST/; curl -s -m 10 https://$SITE_HOST/ | cmp - "$SITE_DIR/index.html" && echo "the page is the person's file"
```

Success: `200`, then `the page is the person's file`.

```sh
curl -s -m 10 -o /dev/null -w '%{http_code} %{redirect_url}\n' http://$SITE_HOST/
```

Success: `308 https://$SITE_HOST/`.

```sh
ssh $DEPLOY_USER@$SERVER 'cd game && docker compose ps --format "{{.Service}} {{.State}}" | sort | tr "\n" " "; docker compose exec -T caddy caddy validate --config /etc/caddy/Caddyfile 2>&1 | grep -c "Valid configuration"'
```

Success: every service `running`, then `1`.

## Later changes

The person edits and commits. You send:

```sh
rsync -a --delete --exclude .git "$SITE_DIR/" $DEPLOY_USER@$SERVER:game/site/
```

Nothing needs restarting. Verify with the first check above.

## Roll back

- **An earlier version of the page:** the person checks out the earlier commit in `SITE_DIR`; you send it as above.
- **Take the site away:** on the server, remove `game/sites/www.caddy` and the `SITE_HOST` line from `.env`, then
  `docker compose up -d caddy`.
- **Cannot be undone:** the certificate's name is in public certificate logs from the moment it is issued.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- writing or changing what the page says, beyond what the person asked for;
- publishing a page that still has placeholder text, or that contains anything that looks like a password;
- making or changing a DNS record, or asking for a certificate for a name the person has not approved;
- `docker compose up -d` without the word `caddy` after it: that would restart the game as well;
- `unrecognized global option` in the web server's log: a file in `game/sites` has no name set in `.env`.
