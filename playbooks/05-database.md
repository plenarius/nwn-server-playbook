# Playbook 5. Add the database (tier 1)

For an agent. The chapter for people is [`chapters/05-database.md`](../chapters/05-database.md). Follow the steps in
order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer, unless it starts with `ssh`.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `SERVER` | The server's address or name | none: a person gives it |
| `DEPLOY_USER` | The account made in playbook 1 | `nwn` |

Secrets: the game's database password (`NWNX_SQL_PASSWORD` in `~/game/.env`) and the database administrator's
password (`MARIADB_ROOT_PASSWORD` in `~/game/db.env`). Step 2 makes both on the server without showing them. Never
print them, and never run a command whose output contains them: `cat .env`, `cat db.env`,
`docker compose config`, `docker inspect` of a container without a `-f` format, or `env` inside a container.

## Preconditions

Playbook 4 is done, the game is healthy, and there is no database yet:

```sh
ssh $DEPLOY_USER@$SERVER 'cd game && docker inspect -f "{{.State.Health.Status}}" game-nwserver-1; ls -d db db.env 2>/dev/null | wc -l; grep -c "^COMPOSE_FILE=" .env'
```

Success: `healthy`, `0`, `0`.

Step 3 stops the game for about half a minute. If players may be on the server, stop and ask first.

## Steps

### 1. Copy the files

```sh
scp templates/game/compose.db.yaml templates/game/.env.db.example templates/game/db.env.example $DEPLOY_USER@$SERVER:game/
```

Success: exit status 0.

### 2. Write the settings and make the passwords

```sh
ssh $DEPLOY_USER@$SERVER 'cd game && cat .env.db.example >> .env && cp db.env.example db.env && chmod 600 db.env && sed -i "s|^NWNX_SQL_PASSWORD=.*|NWNX_SQL_PASSWORD=$(openssl rand -hex 12)|" .env && sed -i "s|^MARIADB_ROOT_PASSWORD=.*|MARIADB_ROOT_PASSWORD=$(openssl rand -hex 12)|" db.env && grep -c "^NWNX_SQL_PASSWORD=." .env && grep -c "^MARIADB_ROOT_PASSWORD=." db.env && stat -c %a .env db.env'
```

Success: `1`, `1`, `600`, `600`. Tell the person where the two passwords are, for them to read.

### 3. Start both and wait for healthy

```sh
ssh $DEPLOY_USER@$SERVER 'cd game && docker compose up -d && for i in $(seq 90); do s=$(docker inspect -f "{{.State.Health.Status}}" game-nwserver-1); [ "$s" = healthy ] && break; sleep 2; done; docker compose ps --format "{{.Service}} {{.Health}}"'
```

Success: `mariadb healthy` and `nwserver healthy`. The first start downloads the database image and took under a
minute on the test.

### 4. See that the game connected

```sh
ssh $DEPLOY_USER@$SERVER 'cd game && docker compose logs nwserver | grep -c "NWNX_SQL.*Reconnect successful"; docker compose logs nwserver | grep -c "Loaded plugin.*NWNX_SQL"'
```

Success: two numbers, each `1` or more. A line `Database connection lost. Reconnecting..` just before
`Reconnect successful.` is normal at every start.

### 5. Fetch the script file that goes with the SQL plugin

Every NWNX plugin has a script file, and a script can only call the plugin when that file is at hand. This fetches
the one for the SQL plugin, from the exact version of NWNX that is running, into the server's `development`
folder:

```sh
ssh $DEPLOY_USER@$SERVER 'cd game && REV=$(docker inspect game-nwserver-1 -f "{{index .Config.Labels \"org.opencontainers.image.revision\"}}") && sudo curl -fsSL -o home/development/nwnx_sql.nss https://raw.githubusercontent.com/nwnxee/unified/$REV/Plugins/SQL/NWScript/nwnx_sql.nss && sudo grep -c "NWNX_SQL_ExecuteQuery" home/development/nwnx_sql.nss'
```

Success: `2`. No restart is needed.

## Verify

The game writes a row and the database shows it. The first command types two lines at the game's console and leaves
it properly; the second reads the row back and removes the test table.

```sh
ssh $DEPLOY_USER@$SERVER '(sleep 2; printf "%s\r" "evalx NWNX_SQL_ExecuteQuery(\"CREATE TABLE IF NOT EXISTS playbook_check (said VARCHAR(40))\");"; sleep 2; printf "%s\r" "evalx NWNX_SQL_ExecuteQuery(\"INSERT INTO playbook_check VALUES (1)\");"; sleep 2; printf "\020\021"; sleep 1) | timeout 30 script -qfc "docker attach game-nwserver-1" /dev/null >/dev/null'
ssh $DEPLOY_USER@$SERVER 'cd game && docker compose exec -T mariadb sh -c "mariadb -u\"\$MARIADB_USER\" -p\"\$MARIADB_PASSWORD\" \"\$MARIADB_DATABASE\" -N -e \"SELECT COUNT(*) FROM playbook_check; DROP TABLE playbook_check\""'
```

Success: `1`.

The database is closed to the outside. From a machine that is not the server:

```sh
timeout 4 bash -c "</dev/tcp/$SERVER/3306" 2>/dev/null && echo "open"
```

Success: no output.

The game never sees the administrator's password:

```sh
ssh $DEPLOY_USER@$SERVER 'cd game && docker compose exec -T nwserver env | grep -c MARIADB_ROOT; grep -c MARIADB_ROOT .env'
```

Success: `0` and `0`.

```sh
templates/game/nwn-status.py $SERVER
```

Success: the game still answers.

## Roll back

- **Take the database away again and keep its data:** remove the lines that step 2 added to `.env` (from the line
  `# ---- The database` to the end), then `docker compose up -d --remove-orphans`. The folder `db` stays.
- **Cannot be undone by you:** deleting the folder `db`. On a server that has been played on, it holds everything
  the module has stored. A person deletes it, never you.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- step 3 on a server that may have players on it;
- changing either password after the database exists (the chapter's step 7 has the way; it needs a person's yes);
- a different `MARIADB_VERSION` on a database that already has data, and above all an older one;
- deleting or moving the folder `db`;
- any command whose output would show a password;
- `Access denied` in the game's log after step 3.
