# Chapter 5. The database

**Status:** tier 1 is written and tested. Tier 2 (changing the tables safely as your module grows) and tier 3
(queue tables, a read-only account for looking things up) are not written yet.

## What you learn

How to give your game server a real database, MariaDB, running beside it on the same machine, and how to prove that
a script in the game can write to it.

When you're done, you'll have:

- a database in its own container that only the game can reach, with nothing about it open to the internet;
- the NWNX plugin for SQL switched on and connected;
- a row in a table that the game itself wrote, which you then read back from the database;
- two passwords that do different jobs, kept in different files, and the knowledge of how to change one later.

You don't need to know SQL for this chapter. You'll type two short lines of it, and they're given.

**Time:** about ten minutes. Starting both servers for the first time, download included, took 36 seconds on the
test machine.

## What Layonara does

- **MariaDB beside the game.** Our game host runs MariaDB 10.11 in the same Compose file as the game server, and
  nearly everything our module remembers goes through the NWNX SQL plugin into it.
- **Some things travel with the character instead.** A few values are stored inside each character's own file, in
  the small database the game itself provides, so they go wherever the character goes.
- **The game has its own account.** It can do anything inside the game's database, and nothing outside it. It can't
  create accounts or hand out rights.
- **Tables change by dated files.** Every change to our tables is a small dated file, applied by a tool that keeps
  a list of what has been applied. That is tier 2 of this chapter.
- **Ours is reachable on our private network,** because a second machine needs it. In tier 1 nothing else needs
  your database, so yours gets no port at all.
- **Ours is twenty years old,** and it shows in one place: its text is stored in an older encoding called latin1. A
  new database starts on today's standard, and yours will.

## The human playbook

Each step carries a label: GENERIC (the same for any server), ADAPT (works once you change the things it names) or
LAYONARA-ONLY (something we do that you probably shouldn't copy).

This chapter adds three files to the `templates/game` folder you met in chapter 4:
[`compose.db.yaml`](../templates/game/compose.db.yaml), which describes the database,
[`.env.db.example`](../templates/game/.env.db.example), a few lines for your settings, and
[`db.env.example`](../templates/game/db.env.example), which holds one password.

`SERVER` is your machine's address or name, as before.

### 1. GENERIC. Know what is kept where

It helps to have the map before you add to it:

- **Characters** are files. The server keeps them in `home/servervault`, and they have nothing to do with the
  database.
- **Everything your scripts want to remember** goes in the database: who owns which house, what is in the bank,
  which quests are done. That is this chapter.
- **The game also has a small database of its own** built in, which needs no setting up. It's fine for small
  things. A separate database earns its place when the data grows, when you want to look at it from outside the
  game, and when you want to back it up properly.

### 2. GENERIC. Copy the new files to the server

From this repository, on your own computer:

```sh
scp templates/game/compose.db.yaml templates/game/.env.db.example templates/game/db.env.example nwn@SERVER:game/
```

### 3. ADAPT. Add the settings and choose two passwords

Change: the two passwords.

On the server:

```sh
ssh nwn@SERVER
cd game
cat .env.db.example >> .env
cp db.env.example db.env && chmod 600 db.env
nano .env       # set NWNX_SQL_PASSWORD, near the end
nano db.env     # set MARIADB_ROOT_PASSWORD
```

`openssl rand -hex 12` makes a good password, and you'll want two different ones. Here is why there are two:

- **The game's password** (`NWNX_SQL_PASSWORD`, in `.env`) belongs to a small account that can only work inside the
  game's own database. The game uses it all day.
- **The administrator's password** (`MARIADB_ROOT_PASSWORD`, in `db.env`) can do anything to the database. It lives
  in a file of its own so that the game server never even sees it. If a script in your module ever goes wrong, the
  worst it can touch is the game's own data.

The first of the new lines in `.env`, `COMPOSE_FILE=...`, tells Docker to read both Compose files from now on. You
keep typing the same `docker compose` commands as in chapter 4.

### 4. GENERIC. Start them

```sh
docker compose up -d
docker compose ps
```

The game stops for about half a minute while this happens, so it's a kindness to do it when nobody is playing. The
database starts first. The game starts once the database says it is ready, and both should end up `(healthy)`.

Then look at what the game said about it:

```sh
docker compose logs nwserver | grep NWNX_SQL
```

You're looking for `Reconnect successful.` and `Loaded plugin ... NWNX_SQL.so`. Just before them there is a line
that looks alarming and isn't: `Database connection lost. Reconnecting..` appears at every start, because that is
simply how the plugin makes its first connection.

### 5. GENERIC. Fetch the script file that goes with the plugin

In chapter 4 I said each plugin comes with a script file. Here is the first one you need. A script can only call
the SQL plugin when `nwnx_sql.nss` is at hand, and it should come from the same version of NWNX that you're
running. This asks the running server which version that is, and fetches the matching file:

```sh
REV=$(docker inspect game-nwserver-1 -f '{{index .Config.Labels "org.opencontainers.image.revision"}}')
sudo curl -fsSL -o home/development/nwnx_sql.nss https://raw.githubusercontent.com/nwnxee/unified/$REV/Plugins/SQL/NWScript/nwnx_sql.nss
```

It lands in the server's `development` folder, where the server notices it straight away. When your own module
arrives in chapter 6, these files move into the module and this copy can go.

### 6. GENERIC. Let the game write something

This is the part I like. Attach to the server's console, as in chapter 4:

```sh
docker attach game-nwserver-1
```

and type these two lines, one at a time:

```
evalx NWNX_SQL_ExecuteQuery("CREATE TABLE IF NOT EXISTS hello (said VARCHAR(40))");
evalx NWNX_SQL_ExecuteQuery("INSERT INTO hello VALUES ('from the game')");
```

`evalx` is a console command that NWNX adds. It runs one line of script, with the NWNX script files already
included. After each line the server answers with `Successful SQL query`.

Leave the console with Ctrl-P and then Ctrl-Q, as before, and ask the database what it has:

```sh
docker compose exec mariadb sh -c 'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" -e "SELECT * FROM hello"'
```

You should see one row that says `from the game`. A script inside your game server wrote that, and you just read it
from outside the game. Everything a persistent world remembers is built from this.

That last command is worth keeping. It opens the database as the game's own account without you typing a password,
because the container already knows it. Leave off the `-e "..."` part and you get a prompt where you can look
around; `exit` leaves it.

If `evalx` answers `was blocked due to configuration`, the last line of `.env.db.example` didn't make it into your
`.env`. If it answers `UNDEFINED IDENTIFIER`, step 5 was missed.

### 7. GENERIC. Changing a password later

The database reads both passwords from your files exactly once: the first time it starts with an empty `db` folder.
After that it keeps them inside itself, and changing a file changes nothing in the database. This surprises nearly
everyone, me included.

To change the game's password:

1. Put the new password in the `NWNX_SQL_PASSWORD` line of `.env`.
2. `docker compose up -d`. The game will now be refused by the database, and its log will say `Access denied`.
   That's expected for the next minute.
3. Tell the database to use the password your settings now say:

   ```sh
   docker compose exec mariadb sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -e "ALTER USER \"$MARIADB_USER\"@\"%\" IDENTIFIED BY \"$MARIADB_PASSWORD\""'
   ```

4. `docker compose restart nwserver`, and check the log as in step 4.

### 8. GENERIC. What to expect when things go wrong

I stopped the database under a running game to see what would happen, so you'd know before it happens to you.

- **The game keeps running** when the database stops. A script that tries to write during that time loses that
  write.
- **The game finds the database again by itself** when it comes back. Its log says `Reconnect successful.`
- **After a reboot both come back by themselves.** The game may be up a few seconds before the database is ready,
  and it simply keeps trying until it gets in. On the test it got in on its thirteenth try.
- **Your data is in the folder `db`,** next to `home` and `logs`. It survived removing both containers and making
  them again. Please don't copy that folder as a backup while the database is running; chapter 12 does backups
  properly.

### 9. LAYONARA-ONLY. The older text encoding

Our database stores text as latin1 because it was created long before today's standard was common. Please don't
copy that. Leave a new database on MariaDB's own default, which is what the template does.

## The agent playbook

If you work with an AI agent, [`playbooks/05-database.md`](../playbooks/05-database.md) has these same steps in a
fixed shape it can follow. It makes both passwords on the server without ever showing them, and it names the
commands an agent must not run because their output would.

## Lessons

These are the things we learned the slow way, written down so you don't have to. The dates are when they happened.

- **The database keeps the password it was born with (2026-11-08).** We went looking for why an administrator
  password in our settings didn't work. The database's files were older than those settings, and the database had
  quietly kept the password it was first created with. Step 7 exists because of that.
- **Give the game a small account of its own.** Ours can do everything inside the game's database and nothing
  beyond it. A module is a lot of scripts written by a lot of hands over a lot of years, and it's a comfort to know
  what the worst case is.
- **Keep the administrator's password away from the game.** Everything in the game's settings file is handed to the
  game server, where any script can read it. That is why the administrator's password has a file of its own.
- **Run the steps from a clean start before you trust them (2026-11-18).** The check in step 6 worked the first
  time I tried it and failed on a clean machine, because I had copied one file by hand and forgotten. Step 5 is
  that file. I mention it because the same thing will happen to you with your own notes, and it's nobody's fault.

## Tested

On 2026-11-18, on a fresh Hetzner cloud server of the smallest shared type that had been through chapters 1 and 4,
with `nwnxee/unified:ed79330` and MariaDB 11.8:

- that neither server starts while the game's database password is empty, and that the database refuses to start
  without an administrator's password;
- a first start of both, download included, in 36 seconds;
- the game writing two rows from its console and the database showing them;
- that the database's port can't be reached from outside, and that the administrator's password is not in the
  game's container or in `.env`;
- that the data survives removing both containers and making them again;
- changing the game's password the wrong way (refused, as step 7 describes) and then the right way;
- stopping the database under a running game, and starting it again;
- a reboot of the machine;
- the same check on MariaDB 10.11, the version we run ourselves, with a fresh `db` folder;
- the whole agent playbook, run as written on a clean folder.

With nobody online, the database used about 90 MB of memory beside the game's 80 MB, and its folder was 162 MB
before any real data.

Not tested: text with accented letters going from a player through the game into the database, what players notice
while the database is away, a database with real load, and moving an existing database from one MariaDB version to
another.
