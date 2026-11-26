# Playbook 5, tier 2. Migrations with a ledger

For an agent. The chapter for people is [`chapters/05-database.md`](../chapters/05-database.md), section "Tier 2".
Follow the steps in order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer. The commands work the same whether
the game runs with plain Docker Compose or in Coolify: the scripts find the containers by their Compose service
names.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `GAME` | The game host's address | none: a person gives it |
| `DEPLOY_USER` | The deploy user | `nwn` |
| `REPO_DIR` | The module's repository, on this computer | `~/mymodule` |

Secrets: none pass through you. The scripts log in to the database as the game's account with the password that is
already inside the database container; never print it, and never run `env` or `docker inspect` without `-f` on
either container. The administrator's password (`~/game/db.env`) is not used here at all.

## Preconditions

The game and its database are healthy, and a backup less than 36 hours old exists:

```sh
ssh $DEPLOY_USER@$GAME 'for s in nwserver mariadb; do docker inspect -f "{{.State.Health.Status}}" $(docker ps -q --filter label=com.docker.compose.service=$s); done; cd game && find backups -maxdepth 1 -name "2*" -mmin -2160 | wc -l; ls backup.sh'
```

Success: `healthy`, `healthy`, a number of `1` or more, `backup.sh`. With no recent backup, run
`ssh $DEPLOY_USER@$GAME 'cd game && sudo ./backup.sh | tail -1'` first.

## Steps

### 1. The scripts on the game host

```sh
scp templates/game/migrate.sh templates/game/restore-db.sh templates/game/release.sh $DEPLOY_USER@$GAME:game/
ssh $DEPLOY_USER@$GAME 'cd game && ./migrate.sh status; echo "exit $?"'
```

Success: a line `N applied, M waiting` and `exit 0`. A line starting `PROBLEM:` means the live ledger and the game
folder disagree: stop and ask.

### 2. The migrations folder in the module's repository

Only if `$REPO_DIR/migrations` does not exist yet:

```sh
[ -d "$REPO_DIR/migrations" ] && echo "already there" || { cp -r templates/module/migrations "$REPO_DIR/" && ls "$REPO_DIR/migrations"; }
```

Success: `already there`, or the two example files. Tell the person that `0001` must describe the tables their
module already has; write that file with them, with `CREATE TABLE IF NOT EXISTS`, before going on.

New migrations you write: the next free number, `NNNN-lowercase-words.sql`; every statement ends with `;`; every
statement is safe to run twice (`IF NOT EXISTS`, `INSERT IGNORE`). Never edit a file that the ledger already lists.

### 3. Send the folder

```sh
ssh $DEPLOY_USER@$GAME 'mkdir -p incoming && rm -rf incoming/migrations'
scp -r "$REPO_DIR/migrations" $DEPLOY_USER@$GAME:incoming/
ssh $DEPLOY_USER@$GAME 'cd game && MIGRATIONS=~/incoming/migrations ./migrate.sh status; echo "exit $?"'
```

Success: `exit 0`, and the `waiting:` lines name exactly the files the person expects. Any `PROBLEM:` line: stop and
ask. Never fix it by editing or deleting a file in the ledger, or a row of the ledger.

### 4. Rehearse on a copy

```sh
ssh $DEPLOY_USER@$GAME 'df -h --output=avail /var/lib/docker | tail -1; cd game && du -sh db | cut -f1; MIGRATIONS=~/incoming/migrations ./migrate.sh rehearse; echo "exit $?"'
```

Success: free space well above the size of `db`, then `rehearsal passed` and `exit 0`. The live database is not
touched. If it fails, report the error line; a file that failed has not run anywhere live and may be corrected,
then repeat steps 3 and 4.

### 5. Apply, inside a release

**Ask first.** A release stops the game for a few seconds and disconnects players. Wait for a yes for this release.

If the release also brings a module, haks or a talk table, follow playbook 16 from its step 4; the files from step
3 here are already in `~/incoming`. If it brings migrations only:

```sh
ssh $DEPLOY_USER@$GAME 'cd game && sudo ./release.sh 2>&1 | grep -v -e "^-*$"; echo "exit ${PIPESTATUS[0]}"'
```

Success: `rehearsal passed`, `game stopped`, `applying ...` for each waiting file, `game started`,
`the game is healthy again`, `exit 0`.

If it ends `release stopped before anything changed`, nothing changed and the game kept running: report it. If it
ends `a migration failed on the live database`, the old game is back and the ledger is unchanged: report the error
and the backup named, and stop.

## Verify

```sh
ssh $DEPLOY_USER@$GAME 'cd game && ./migrate.sh status && ./migrate.sh apply'
ssh $DEPLOY_USER@$GAME 'docker exec -i $(docker ps -q --filter label=com.docker.compose.service=mariadb) sh -c "MYSQL_PWD=\"\$MARIADB_PASSWORD\" mariadb -u\"\$MARIADB_USER\" -N \"\$MARIADB_DATABASE\" -e \"SELECT name FROM schema_migrations ORDER BY name\""'
templates/game/nwn-status.py $GAME
```

Success: `N applied, 0 waiting`, then `nothing to apply`; the ledger lists every file in `$REPO_DIR/migrations`; the
game answers with its module.

## Roll back

- **The module back, the database as it is now:** `sudo ./release.sh --undo` in `~/game`. Ask first: it restarts
  the game. It prints the migrations that release applied and the backup made just before.
- **The database back:** no migration has a rollback file. The only way back is restoring the backup made just
  before the release, which loses everything players did since. That is a person's decision and a person's
  command, run in a terminal of their own because it asks them to type `restore`:
  `ssh -t $DEPLOY_USER@$GAME 'cd game && sudo ./restore-db.sh backups/<the backup named>'`. Give them the command;
  don't run it.
- **Cannot be undone:** anything a migration dropped or overwrote, except by that restore.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- any `PROBLEM:` line from `status`;
- step 5, always, and any `release.sh --undo`;
- `restore-db.sh`, always;
- a migration that drops or renames a table or a column, or deletes rows;
- a migration that fails in the rehearsal and that you can't fix without changing what it means;
- changing a file the ledger lists, or writing to `schema_migrations` by hand;
- less free disk on the game host than the size of `~/game/db`;
- anything that would need the database administrator's password.
