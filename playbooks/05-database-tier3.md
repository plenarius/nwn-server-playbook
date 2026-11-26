# Playbook 5, tier 3. A work queue, revision counters and a read-only account

For an agent. The chapter for people is [`chapters/05-database.md`](../chapters/05-database.md), section "Tier 3".
Follow the steps in order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer. The commands work the same whether
the game runs with plain Docker Compose or in Coolify, except step 4, which says where they differ.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `GAME` | The game host's public address | none: a person gives it |
| `CONTROL` | The control host's public address | none: a person gives it |
| `DEPLOY_USER` | The deploy user on both | `nwn` |
| `REPO_DIR` | The module's repository, on this computer | `~/mymodule` |
| `GAME_PRIVATE` | The game host's private address (chapter 1) | `10.77.0.2` |
| `CONTROL_PRIVATE` | The control host's private address, which the accounts may log in from | `10.77.0.1` |
| `READER` | The read-only account's name | `website` |

Secrets: the new accounts' passwords, made in step 6 into files on this computer that only the person can read
(`umask 077`). They travel on standard input only: never print them, never put them on a command line or in an
`echo`. `~/game/db.env` (the database administrator's password) is read only by `db-accounts.sh` on the game host;
never `cat`, `grep` or copy it, and never run `env` or `docker inspect` without `-f` on either container.

## Preconditions

Tier 2 of this chapter is in place, the game is healthy, and the private network answers:

```sh
ssh $DEPLOY_USER@$GAME 'cd game && ./migrate.sh status | head -1; ls release.sh backup.sh; docker inspect -f "{{.State.Health.Status}}" $(docker ps -q --filter label=com.docker.compose.service=nwserver)'
ssh $DEPLOY_USER@$CONTROL "ping -c 1 -W 2 $GAME_PRIVATE > /dev/null && echo private ok; docker image ls -q mariadb:11.8 | grep -c . || docker pull -q mariadb:11.8"
ls $REPO_DIR/migrations $REPO_DIR/src/nss/nwnx_sql.nss
```

Success: `N applied, 0 waiting`, `release.sh backup.sh`, `healthy`; `private ok` and a number or an image name; the
module's migrations and `nwnx_sql.nss`. Anything else: stop and ask.

## Steps

### 1. The two migrations, under the next numbers

```sh
cd $REPO_DIR/migrations && n=$(ls | sed -n 's/^\([0-9]\{4\}\)-.*\.sql$/\1/p' | sort | tail -1); cd - > /dev/null
ls $REPO_DIR/migrations | grep -E -e '-work-queue\.sql$' -e '-revisions\.sql$' || {
  cp templates/module/database/work-queue.sql $REPO_DIR/migrations/$(printf %04d $((10#$n + 1)))-work-queue.sql
  cp templates/module/database/revisions.sql $REPO_DIR/migrations/$(printf %04d $((10#$n + 2)))-revisions.sql
  ls $REPO_DIR/migrations | tail -2; }
```

Success: two file names, `NNNN-work-queue.sql` and `NNNN-revisions.sql`, either already there or just made.

### 2. The scripts in the module

```sh
for f in templates/module/database/*.nss; do [ -e "$REPO_DIR/src/nss/${f##*/}" ] || cp "$f" "$REPO_DIR/src/nss/"; done
grep -l '^ *ExecuteScript("db_poll");' $REPO_DIR/src/nss/*.nss | grep -v '/db_poll\.nss$' || echo "not started anywhere"
```

Success: the name of the module's `OnModuleLoad` script, or `not started anywhere`. In the second case, find the
`OnModuleLoad` script (`Mod_OnModLoad` in `module.ifo.json`; `mod_load` in chapter 6's module) and add
`    ExecuteScript("db_poll");` as the last line of its `main`. Show the person the change. Then build as in
playbook 6 and commit on a branch; the person merges it.

New job kinds you write: `wq_<kind>.nss`, at most 13 characters after `wq_`, as in the chapter's step 24: read every
`GetScriptParam` into a variable first, finish with `Queue_Finish` within two minutes, and make the work safe to run
twice.

### 3. Release the migrations with the module

**Ask first.** A release stops the game for a few seconds. Wait for a yes for this release.

Put the built `.mod` and the migrations in `~/incoming`, as playbook 16 does, and release:

```sh
ssh $DEPLOY_USER@$GAME 'mkdir -p incoming && rm -rf incoming/migrations'
scp -r $REPO_DIR/migrations $DEPLOY_USER@$GAME:incoming/
scp $REPO_DIR/*.mod $DEPLOY_USER@$GAME:incoming/
ssh $DEPLOY_USER@$GAME 'cd game && sudo ./release.sh 2>&1 | grep -v -e "^-*$"; echo "exit ${PIPESTATUS[0]}"'
```

Success: `rehearsal passed`, `applying NNNN-work-queue.sql`, `applying NNNN-revisions.sql`, `installed
home/modules/...`, `the game is healthy again`, `exit 0`. On a stop, follow playbook 5 tier 2's step 5.

Then a test job, as the game's own account:

```sh
ssh $DEPLOY_USER@$GAME 'db=$(docker ps -q --filter label=com.docker.compose.service=mariadb); q() { docker exec -i $db sh -c "MYSQL_PWD=\"\$MARIADB_PASSWORD\" mariadb -u\"\$MARIADB_USER\" --batch --skip-column-names \"\$MARIADB_DATABASE\""; }; echo "INSERT INTO work_queue (kind, args, added_by) VALUES (\"announce\", \"A test from the playbook\", \"agent\");" | q; sleep 12; echo "SELECT status, result FROM work_queue WHERE added_by = \"agent\" ORDER BY id DESC LIMIT 1;" | q'
```

Success: `done` and `told N online`. `queued` means the poller isn't running: check the game's log for
`db_poll: started` and step 2's line.

### 4. The database on the private address

**Ask first.** This lets every machine on the private network reach the database, and it restarts the database
and the game with it: players are disconnected for a few seconds. Wait for a yes.

With plain Compose (the game host has `~/game/compose.db.yaml` and a running `game-mariadb-1`):

```sh
scp templates/game/compose.db-private.yaml $DEPLOY_USER@$GAME:game/
ssh $DEPLOY_USER@$GAME "cd game && grep -q '^DB_PRIVATE_ADDRESS=' .env || { sed -i '/^COMPOSE_FILE=/{/compose.db-private.yaml/!s/\$/:compose.db-private.yaml/}' .env && echo 'DB_PRIVATE_ADDRESS=$GAME_PRIVATE' >> .env; }; grep -E '^(COMPOSE_FILE|DB_PRIVATE_ADDRESS)=' .env; docker compose up -d 2>&1 | tail -2"
```

Success: `COMPOSE_FILE=...:compose.db-private.yaml`, `DB_PRIVATE_ADDRESS=...`, the containers `Started` or
`Running`.

In Coolify: ask the person to add these lines to the `mariadb` service in the game service's compose file, under its
`volumes`, and redeploy; then go on:

```yaml
    ports:
      - "10.77.0.2:3306:3306"
```

Either way, check:

```sh
ssh $DEPLOY_USER@$GAME 'docker ps --format "{{.Ports}}" --filter label=com.docker.compose.service=mariadb'
ssh $DEPLOY_USER@$CONTROL "timeout 4 bash -c '</dev/tcp/$GAME_PRIVATE/3306' && echo private open"
timeout 4 bash -c "</dev/tcp/$GAME/3306" 2>/dev/null && echo "PUBLIC OPEN" || echo "public closed"
```

Success: `10.77.0.2:3306->3306/tcp` (and nothing with `0.0.0.0`), `private open`, `public closed`. `PUBLIC OPEN`:
undo this step at once (Roll back) and stop.

### 5. The account script and its timer

```sh
scp templates/game/db-accounts.sh templates/game/db-accounts-sync.service templates/game/db-accounts-sync.timer $DEPLOY_USER@$GAME:game/
ssh $DEPLOY_USER@$GAME "cd game && sed -i 's|/home/nwn/|/home/$DEPLOY_USER/|; s|^User=nwn|User=$DEPLOY_USER|' db-accounts-sync.service && ./db-accounts.sh sync --dry-run && sudo cp db-accounts-sync.service db-accounts-sync.timer /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now -q db-accounts-sync.timer && systemctl is-active db-accounts-sync.timer"
```

Success: a list of `GRANT SELECT ...` lines or `the readers' rights are in step with the tables`, then `active`.
The timer's first run starts at once and makes those grants.
Show the person every column list in a `GRANT SELECT (...)` line, and ask whether any other column there is private
(a player's address, account name, anything personal). If so, they add its name to `DENY_COLUMNS` in
`~/game/db-accounts.sh`; run the dry run again.

### 6. The read-only account

**Ask first.** Name the account, the address it may log in from and what it may read. Wait for a yes.

```sh
umask 077; [ -s $READER.password ] || openssl rand -hex 16 > $READER.password
ssh $DEPLOY_USER@$GAME "cd game && ./db-accounts.sh reader $READER $CONTROL_PRIVATE" < $READER.password
ssh $DEPLOY_USER@$GAME "cd game && ./db-accounts.sh show $READER"
```

Success: `made website, which may log in from 10.77.0.1 only`; `show` lists `GRANT game_reader`, `MAX_USER_CONNECTIONS 5
MAX_STATEMENT_TIME 10` and `GRANT SELECT ON ...` lines for the game's tables only. `exists already`: stop and ask.

Tell the person where the password file is (`$READER.password` in this repository's folder): it goes into the
service's own settings, by them, and then the file can be deleted.

An account that may add jobs, only if the person wants one for a website: the same with
`./db-accounts.sh queue <name> $CONTROL_PRIVATE`, after its own yes.

## Verify

From the control host, as the reader, the password on standard input:

```sh
{ cat $READER.password; printf '%s\n' "SELECT COUNT(*) FROM work_queue;" "SELECT name, rev FROM revisions;" "INSERT INTO work_queue (kind) VALUES ('announce');" "SELECT User FROM mysql.user;"; } |
  ssh $DEPLOY_USER@$CONTROL "read -r p; MYSQL_PWD=\$p docker run --rm -i -e MYSQL_PWD --network host mariadb:11.8 mariadb -h $GAME_PRIVATE -u$READER --batch -f nwn 2>&1"
{ cat $READER.password; echo "SELECT 1;"; } |
  ssh $DEPLOY_USER@$GAME "read -r p; MYSQL_PWD=\$p docker run --rm -i -e MYSQL_PWD --network host mariadb:11.8 mariadb -h $GAME_PRIVATE -u$READER --batch nwn 2>&1"
templates/game/nwn-status.py $GAME
```

Success: a count; `server` with a number; `INSERT command denied`; `SELECT command denied ... mysql`. Then, from the
game host's own address, `Access denied for user 'website'@'10.77.0.2'`. The game answers with its module.

## Roll back

- **An account:** `ssh $DEPLOY_USER@$GAME 'cd game && ./db-accounts.sh drop <name>'`. Ask first: the service using
  it stops working. The script refuses any account it didn't make.
- **The timer:** `sudo systemctl disable --now db-accounts-sync.timer` on the game host. Accounts keep the rights
  they have.
- **The private address:** remove `:compose.db-private.yaml` from `COMPOSE_FILE` and the `DB_PRIVATE_ADDRESS` line
  in `~/game/.env`, and `docker compose up -d`; in Coolify, the person removes the `ports` lines and redeploys. Ask
  first: everything on the control host that reads the database stops.
- **The poller:** remove the `ExecuteScript("db_poll");` line and release the module. Jobs added meanwhile wait in
  the table.
- **The tables:** they stay. Dropping them is a new migration and a person's decision.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- step 3, step 4 and step 6, always, and every `drop`;
- the database's port on any address but the private one, or `public closed` not seen in step 4;
- an account allowed from `%`, from a public address, or with more than `SELECT` (other than `queue`);
- a column in a `GRANT SELECT (...)` list that might be private, or any change to `DENY_COLUMNS`;
- a job kind that gives players items, gold or experience, or deletes anything;
- a job left `claimed` for more than ten minutes, or many ending `failed`;
- anything that would need the database administrator's password outside `db-accounts.sh`, or a grant typed by
  hand.
