# Playbook 10, tier 3. Reports, a chat bridge and a roster

For an agent. The chapter for people is [`chapters/10-discord-bot.md`](../chapters/10-discord-bot.md), section
"Tier 3". Follow the steps in order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer, with `gh` signed in as someone who
may change the bot's repository and the reports repository's settings.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `GAME` | The game host's public address | none: a person gives it |
| `CONTROL` | The control host's public address | none: a person gives it |
| `DEPLOY_USER` | The deploy user on both | `nwn` |
| `REPO_DIR` | The module's repository, on this computer | `~/mymodule` |
| `BOT_DIR` | A checkout of the bot's repository (playbook 10 tier 2's `BOT_REPO`), on this computer | `~/mybot` |
| `BOT_HOST` | The name GitHub calls the bot on (tier 2) | none: a person gives it |
| `REPORTS_REPO` | The private reports repository, as `owner/name` | none: a person gives it |
| `CONTROL_PRIVATE` | The control host's private address | `10.77.0.1` |
| `BOT_DB_USER` | The bot's database account | `botchat` |
| `OPS_DB_USER` | The operations API's read-only database account | `opsreader` |

Secrets: the two accounts' passwords, made in steps 5 and 6 into files on this computer that only the person can
read (`umask 077`); they travel on standard input only. The Discord token, the GitHub token and the webhook secret
are in the bot's settings, which a person fills in, in Coolify: never print them, never print a line of them, and
never print an API response for the bot's or the operations API's variables. `READ_KEY` is the operations API's
read key and `COOLIFY_TOKEN` Coolify's (Root, as in playbook 3), both placed in this shell by a person.

## Preconditions

```sh
ssh $DEPLOY_USER@$GAME 'cd game && ./migrate.sh status | head -1; ls db-accounts.sh release.sh; docker inspect -f "{{.State.Health.Status}}" $(docker ps -q --filter label=com.docker.compose.service=nwserver)'
ls $REPO_DIR/src/nss/db_poll.nss $REPO_DIR/src/nss/inc_queue.nss $REPO_DIR/tests/run.sh
grep -l 'ExecuteScript("db_poll");' $REPO_DIR/src/nss/*.nss | grep -v '/db_poll\.nss$'
git -C $BOT_DIR status --short | wc -l
gh repo view $REPORTS_REPO --json visibility -q .visibility
curl -s -o /dev/null -w '%{http_code}\n' https://$BOT_HOST/health
```

Success: `N applied, 0 waiting`; `db-accounts.sh release.sh`; `healthy`; the three module files; the name of the
module's `OnModuleLoad` script; `0` (a clean bot checkout); `PRIVATE`; `200`. Anything else: stop and ask.

## Steps

### 1. The module: migrations, scripts, tests, and the start line

```sh
cd $REPO_DIR/migrations && n=$(ls | sed -n 's/^\([0-9]\{4\}\)-.*\.sql$/\1/p' | sort | tail -1); cd - > /dev/null
ls $REPO_DIR/migrations | grep -E -e '-chat-out\.sql$' -e '-online-players\.sql$' || {
  cp templates/module/bot/chat-out.sql $REPO_DIR/migrations/$(printf %04d $((10#$n + 1)))-chat-out.sql
  cp templates/module/bot/online-players.sql $REPO_DIR/migrations/$(printf %04d $((10#$n + 2)))-online-players.sql
  ls $REPO_DIR/migrations | tail -2; }
for f in inc_bridge chat_bridge wq_chat bridge_start roster_poll; do [ -e $REPO_DIR/src/nss/$f.nss ] || cp templates/module/bot/$f.nss $REPO_DIR/src/nss/; done
for f in templates/module/bot/t_*.nss templates/module/bot/inc_bridge_t.nss; do [ -e $REPO_DIR/tests/nss/${f##*/} ] || cp $f $REPO_DIR/tests/nss/; done
grep -l 'NWNX_Chat_RegisterChatScript' $REPO_DIR/src/nss/*.nss | grep -v '/bridge_start\.nss$' || echo "no other chat script"
grep -l 'ExecuteScript("bridge_start");' $REPO_DIR/src/nss/*.nss || echo "not started anywhere"
```

Success: `NNNN-chat-out.sql` and `NNNN-online-players.sql`; `no other chat script`; the `OnModuleLoad` script's
name, or `not started anywhere`. In that case add `ExecuteScript("bridge_start");` after the `db_poll` line in the
script the precondition named, and show the person the change. A file named instead of `no other chat script`:
stop and ask (NWNX_Chat runs one chat script; the person decides where `Bridge_FromGame` is called from).

### 2. The module's tests

```sh
(cd $REPO_DIR && tests/run.sh --filter t_bridge_,t_roster_ 2>&1 | tail -6)
```

Success: `PASS  t_bridge_clean`, `PASS  t_bridge_hook`, `PASS  t_bridge_wqchat`, `PASS  t_roster_write`, `4 passed,
0 failed, 0 skipped`. Then the person reviews and merges the change in `REPO_DIR` and builds the module as usual.

### 3. NWNX_Chat and UTF-8 on the game host

```sh
ssh $DEPLOY_USER@$GAME 'cd game && for l in NWNX_CHAT_SKIP=n NWNX_SQL_USE_UTF8=true NWNX_SQL_CHARACTER_SET=utf8mb4; do grep -q "^${l%%=*}=" .env || echo "$l" >> .env; done; grep -E "^NWNX_(CHAT_SKIP|SQL_USE_UTF8|SQL_CHARACTER_SET)=" .env'
```

Success: the three lines. They take effect with the restart in step 4. In Coolify, the person adds the same three
to the game service's variables instead.

### 4. Release

**Ask first.** A release stops the game for a few seconds. Wait for a yes for this release.

```sh
ssh $DEPLOY_USER@$GAME 'mkdir -p incoming && rm -rf incoming/migrations'
scp -r $REPO_DIR/migrations $DEPLOY_USER@$GAME:incoming/
scp $REPO_DIR/*.mod $DEPLOY_USER@$GAME:incoming/
ssh $DEPLOY_USER@$GAME 'cd game && sudo ./release.sh 2>&1 | grep -v -e "^-*$"; echo "exit ${PIPESTATUS[0]}"'
sleep 40; ssh $DEPLOY_USER@$GAME 'cd game && docker compose logs --since 3m nwserver 2>&1 | grep -c "bridge_start: chat bridge and roster on"; db=$(docker ps -q --filter label=com.docker.compose.service=mariadb); echo "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name IN (\"chat_out\", \"online_players\");" | docker exec -i $db sh -c "MYSQL_PWD=\"\$MARIADB_PASSWORD\" mariadb -u\"\$MARIADB_USER\" --batch --skip-column-names \"\$MARIADB_DATABASE\""'
```

Success: `applying NNNN-chat-out.sql`, `applying NNNN-online-players.sql`, `the game is healthy again`, `exit 0`;
then `1` (the scripts started) and `2` (both tables). On a stop, follow playbook 5 tier 2's step 5.

### 5. The bot's database account

**Ask first.** Name the account, the address it may log in from (`CONTROL_PRIVATE`) and its two rights. Wait for
a yes.

```sh
umask 077; [ -s $BOT_DB_USER.password ] || openssl rand -hex 16 > $BOT_DB_USER.password
ssh $DEPLOY_USER@$GAME "cd game && ./db-accounts.sh bot $BOT_DB_USER $CONTROL_PRIVATE" < $BOT_DB_USER.password
ssh $DEPLOY_USER@$GAME "cd game && ./db-accounts.sh show $BOT_DB_USER"
```

Success: `made botchat, which may log in from 10.77.0.1 only`; `show` lists `GRANT game_bot`, `GRANT SELECT, INSERT
(args, added_by, kind) ON nwn.work_queue` and `GRANT SELECT ON nwn.chat_out`, and nothing else on the game's
tables. `exists already`: stop and ask.

### 6. The roster in the operations API

**Ask first.** Name the read-only account and the query. Wait for a yes.

```sh
umask 077; [ -s $OPS_DB_USER.password ] || openssl rand -hex 16 > $OPS_DB_USER.password
ssh $DEPLOY_USER@$GAME "cd game && ./db-accounts.sh reader $OPS_DB_USER $CONTROL_PRIVATE" < $OPS_DB_USER.password
```

Success: `made opsreader, which may log in from 10.77.0.1 only`. Tell the person where both password files are.
They add to the operations API's settings (chapter step 15) `MYSQL_HOST=10.77.0.2`, `MYSQL_USER`,
`MYSQL_PASSWORD` and the `ONLINE_SQL` line, and redeploy it, on an API image with nwn-ops-api#6. When they say it's
done:

```sh
printf 'Authorization: Bearer %s\n' "$READ_KEY" | ssh $DEPLOY_USER@$CONTROL "curl -s -o /dev/null -w '%{http_code} ' http://$CONTROL_PRIVATE:8100/api/v1/server/online; curl -s -H @- http://$CONTROL_PRIVATE:8100/api/v1/server/online"
```

Success: `401 {"count":N,"characters":[...]}`. `503` with `ONLINE_SQL` in it: the setting is missing; `503` with a
database error: check the account's address and password.

### 7. The bot's new code

```sh
cp -r templates/bot/. $BOT_DIR/
cd $BOT_DIR && git switch -c tier3-reports-bridge-roster && git add -A && git status --short
python3 -m venv /tmp/bot-venv-$$ && /tmp/bot-venv-$$/bin/pip install -q -r requirements-test.txt && /tmp/bot-venv-$$/bin/python -m pytest -q 2>&1 | tail -1; rm -rf /tmp/bot-venv-$$
cd - > /dev/null
```

Success: the new files (`bot/reports.py`, `bot/bridge.py`, `bot/roster.py`, their tests) and the changed ones;
`N passed`. A file the person changed since tier 2 shows as modified too: show them its diff before going on.
**Ask first**, then push the branch and open a pull request on the bot's repository; the person merges it after
step 9.

### 8. The reports repository's webhook

**Ask first**: this adds a webhook to `REPORTS_REPO`, pointing at `https://BOT_HOST/github`. The person gives
the webhook secret through a private file (`SECRET_FILE`, mode 600), the same one as in the bot's settings. After the
yes:

```sh
python3 -c '
import json, sys
print(json.dumps({"name": "web", "active": True, "events": ["issues", "issue_comment"],
                  "config": {"url": sys.argv[2], "content_type": "json", "secret": open(sys.argv[1]).read().strip(), "insecure_ssl": "0"}}))' \
  $SECRET_FILE "https://$BOT_HOST/github" | gh api -X POST repos/$REPORTS_REPO/hooks --input - -q .id > /tmp/hook-$$.id
sleep 5; gh api repos/$REPORTS_REPO/hooks/$(cat /tmp/hook-$$.id)/deliveries -q '.[0] | "\(.event) \(.status_code)"'; rm -f /tmp/hook-$$.id
```

Success: `ping 200`.

### 9. The bot's settings, and the merge

The person adds the tier 3 settings to the bot in Coolify (chapter step 18): `REPORTS_CHANNEL_ID`,
`REPORTS_REPO`, `GITHUB_TOKEN` (fine-grained, Issues read and write on `REPORTS_REPO` only), `BRIDGE_CHANNEL_ID`,
`BRIDGE_DB_USER`, `BRIDGE_DB_PASSWORD`, `ROSTER_CHANNEL_ID`, and switches on the Message Content intent in the
Developer Portal. Then they merge step 7's pull request, which redeploys the bot. When it's done:

```sh
ssh -f -N -L 8000:localhost:8000 $DEPLOY_USER@$CONTROL 2>/dev/null
cl() { curl -s -X "$1" -H @<(printf 'Authorization: Bearer %s\n' "$COOLIFY_TOKEN") -H 'Content-Type: application/json' ${3:+-d "$3"} "http://localhost:8000/api/v1$2"; }
APP=$(cl GET /applications | python3 -c 'import json,sys; r=[a["uuid"] for a in json.load(sys.stdin) if a["name"]=="bot"]; print(r[0] if len(r)==1 else "")'); echo "application: ${APP:-none or several}"
ssh $DEPLOY_USER@$CONTROL "docker logs --since 5m \$(docker ps -q --filter name=$APP | head -1) 2>&1 | grep -E 'commands synced|chat bridge on|roster posted|Missing settings|must be too|bridge:|roster:' | head"
```

Success: one id; `commands synced to the guild: restart, cancel-restart, report` (or nothing for that line with
`SYNC_COMMANDS=false`), `chat bridge on`, `roster posted: message ...`, and no `bridge:` or `roster:` warnings.
`must be too`: the person completes the setting it names. `bridge: OperationalError: (1045, ...)`: the account's
password or address is wrong.

## Verify

```sh
ssh $DEPLOY_USER@$GAME 'db=$(docker ps -q --filter label=com.docker.compose.service=mariadb); q() { docker exec -i $db sh -c "MYSQL_PWD=\"\$MARIADB_PASSWORD\" mariadb -u\"\$MARIADB_USER\" --batch --skip-column-names \"\$MARIADB_DATABASE\""; }; echo "SELECT status, result FROM work_queue WHERE kind = \"chat\" ORDER BY id DESC LIMIT 3; SELECT COUNT(*) FROM chat_out WHERE created_at > NOW() - INTERVAL 10 MINUTE;" | q'
```

Ask the person to write one line in the bridge channel and to shout one line in the game, then run it. Success:
a `done	shown to N` row, and a count of 1 or more. Then ask them to look at the bridge channel (their shout is there,
under their character's name), at the roster (their character is listed within a minute and a half), and to file
one `/report` and answer it on GitHub with `To reporter: test`: the answer appears in their private thread.

## Roll back

- **A part of the bot:** the person takes its channel setting out (`REPORTS_CHANNEL_ID`, `BRIDGE_CHANNEL_ID` or
  `ROSTER_CHANNEL_ID`) and redeploys; that part is off and the rest runs on. The whole change: revert the merge on
  the bot's repository.
- **The webhook:** `gh api -X DELETE repos/$REPORTS_REPO/hooks/<id>` (ids from `gh api repos/$REPORTS_REPO/hooks -q
  '.[] | "\(.id) \(.config.url)"'`).
- **The accounts:** `ssh $DEPLOY_USER@$GAME 'cd game && ./db-accounts.sh drop <name>'`. Ask first.
- **The module:** remove the `bridge_start` line and release; the two tables can stay (they hold a day of chat and
  the roster, nothing else). Removing them is a new migration, not an edit to the old ones.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- steps 4, 5, 6, 7 (the push) and 8, always;
- another chat script already registered in the module (step 1);
- any post in a channel players can read, or a test report, unless the person asked for it;
- reading a reporter's Discord id out of the bot's `reports.db`;
- printing, copying or moving the bot's settings, the password files, `SECRET_FILE` or `READ_KEY`;
- giving the bot's account any right beyond the two in step 5, or the GitHub token any repository beyond
  `REPORTS_REPO`;
- deleting a webhook, an account, a table or the bot's `/data` volume.
