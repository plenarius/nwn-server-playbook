# Chapter 5. The database

**Status:** all three tiers are written and tested. Tier 1 gives the game a database; tier 2, further down, changes
its tables safely as your module grows; tier 3, at the end, lets websites, bots and reports work with the game
through the database: a work queue, revision counters and a read-only account.

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

## Tier 2. Changing the tables safely

### What you learn

Sooner or later your module wants a new table, or a new column in an old one. In tier 1 a script makes it with
`CREATE TABLE IF NOT EXISTS` and nobody thinks about it again. That stops working well when several people change
the module, when a release has to put the database and the module in step, and when you want to know, six months
later, exactly what was done to your tables and when.

The usual answer has a slightly grand name, **migrations**, and is very simple: every change to the tables is a
small numbered SQL file in your module's repository, and the database keeps a list of the files it has run, which
is called the **ledger**.

When you're done, you'll have:

- a `migrations` folder in your module's repository, numbered `0001-...sql`, `0002-...sql`, and so on;
- a ledger table in the game's database with each file's name, a checksum of its exact contents, and when it ran;
- a script on the game host that runs the waiting files in order, and refuses to run anything if a file that
  already ran has been changed;
- every migration tried first on a throwaway copy of your newest backup, before it reaches the live database;
- releases from chapter 16 that do all of this for you, while the game is stopped and before the new module starts;
- the way back, tested: a restore of the backup made just before.

**Time:** about fifteen minutes to set up. On the test, a release with one migration took 22 seconds, of which the
rehearsal on a copy was about 14, with the game still running for players.

### What Layonara does

- **Every change to our tables is a dated file** in the module's repository, named like
  `2026-10-24-dm-log.sql`. There are about a hundred of them.
- **A ledger table, `schema_migrations`,** records each file's name, a SHA-256 checksum of its contents and when it
  ran. Our tool refuses to continue if a file that ran has since been edited. The ledger in this section is built
  the same way.
- **Every file is safe to run twice.** `CREATE TABLE IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS`, `INSERT IGNORE`
  appear over 350 times in ours.
- **The test database is built from the same files.** Every run of our test suite starts a fresh database with our
  tables' layout and no player data, loads every migration into it, and runs the module's tests against it, so a
  migration is exercised many times before it ever meets the live database.
- **Big changes get a rehearsal of their own.** Our housing rework came with a script that applies its migrations
  to a throwaway database, applies them again, rolls them back, and compares every table before and after.
- **Some changes have a matching rollback file,** about two dozen so far, for the big ones.
- **Applying them is a step in our release order:** stop the server, take a fresh dump of the database, apply, check
  that nothing is waiting, then start the new module.

### The human playbook

You need tier 1 of this chapter, the backup of chapter 12 and the release script of chapter 16. Everything works
the same whether the game runs with plain Docker Compose (tier 1) or in Coolify (chapter 4, tier 2). The examples
use `GAME` for the game host's address.

The files for this section are [`templates/game/migrate.sh`](../templates/game/migrate.sh), which runs the
migrations, [`templates/game/restore-db.sh`](../templates/game/restore-db.sh), which puts a backup back, a new
[`templates/game/release.sh`](../templates/game/release.sh) that knows about migrations, and two example
migrations in [`templates/module/migrations`](../templates/module/migrations).

#### 10. GENERIC. Know what the ledger does

The ledger is a table called `schema_migrations`, kept in the game's own database. Each row is one file that ran:

| name | checksum | applied_at |
|---|---|---|
| `0001-server-starts.sql` | `a7350f92...` | 2026-11-26 14:25:00 |
| `0002-server-starts-module.sql` | `35d49cf8...` | 2026-11-26 14:25:00 |

That's the whole idea, and it does three jobs:

- **It knows what's waiting.** Any file in the folder that isn't in the ledger hasn't run yet, so it runs next.
  Files run in order of their number.
- **It notices a changed file.** The checksum is a fingerprint of the file's exact bytes. If someone edits a file
  that already ran, even a comment, the fingerprints no longer agree and the script stops before running anything.
  A file that ran is history: what it did is in your database now, and editing it changes nothing there. The
  correction is a new file with the next number.
- **It travels with your backups.** It's an ordinary table, so every nightly dump from chapter 12 carries it. A
  database restored from a backup knows exactly which files it has had.

The script runs everything as the game's own account from tier 1, which can change tables inside the game's
database and nothing else. The administrator's password isn't needed, so in Coolify it stays out, as chapter 4
asks.

#### 11. GENERIC. Copy the scripts to the game host

From this repository:

```sh
scp templates/game/migrate.sh templates/game/restore-db.sh templates/game/release.sh nwn@GAME:game/
ssh nwn@GAME 'cd game && ./migrate.sh status'
```

The first `status` makes the ledger table, empty, and says `0 applied, 0 waiting`. The new `release.sh` does
everything the old one did; it only adds the migration steps when a release brings migrations.

#### 12. ADAPT. Start the folder in your module's repository

Change: the first file, to describe the tables your module already has.

```sh
cp -r templates/module/migrations ~/mymodule/
```

A migration's name is four digits, a dash, and a few lowercase words: `0003-bank.sql`. The script ignores anything
else in the folder, and says so, so a misnamed file is noticed.

The first file is a special one. Your database already has tables, made by scripts like chapter 6's example, and
`0001` writes them down: `CREATE TABLE IF NOT EXISTS server_starts (...)`. On your live database it changes nothing,
because the table is there. On an empty database, a new test server or a new team member's, it makes the table.
From now on the folder describes your whole database, and that is a lovely thing to have.

`0002` is a real change: it adds a column. Delete it if you don't want it, or keep it to see the whole process
once.

#### 13. GENERIC. Write a migration that is safe to run twice

Every migration should be harmless the second time. The ledger means it normally runs once, but a restore, a test
database or a half-finished run may meet it again. MariaDB makes this easy:

```sql
CREATE TABLE IF NOT EXISTS bank (player VARCHAR(64) PRIMARY KEY, gold INT NOT NULL DEFAULT 0);
ALTER TABLE bank ADD COLUMN IF NOT EXISTS silver INT NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS bank_gold ON bank (gold);
INSERT IGNORE INTO bank VALUES ('the module', 0);
```

A few more habits that have served us well:

- **End every statement with `;`.** The script adds its own line to record the file, right after yours.
- **One idea per file.** A small file is easy to read in review and easy to reason about when something goes wrong.
- **Add, don't take away.** A new column with a default doesn't bother the module that is running now. Removing or
  renaming one does, so do that in a later release, once no script uses the old name.
- **Two pull requests, one number.** If two people both write `0005-...`, both files still run, in order of their
  full names. If the order matters, renumber one before merging.

Write the module's scripts to expect the new table after the release. The migration and the module that needs it
go out together.

#### 14. GENERIC. Try it on a copy first

This is my favourite part, because it costs nothing. Send the folder to the game host and rehearse:

```sh
cd ~/mymodule
ssh nwn@GAME 'mkdir -p incoming && rm -rf incoming/migrations'
scp -r migrations nwn@GAME:incoming/
ssh nwn@GAME 'cd game && MIGRATIONS=~/incoming/migrations ./migrate.sh status && MIGRATIONS=~/incoming/migrations ./migrate.sh rehearse'
```

`status` lists what's waiting. `rehearse` starts a throwaway MariaDB of the same version as yours, with no network
at all, loads your newest backup into it, runs the waiting files there, then checks that a second run would find
nothing to do. It ends with `rehearsal passed`, and the copy is removed. Your live database is never touched, and
the game keeps running.

Because it's last night's real data, it finds the problems an empty test database can't: the duplicate row, the
column that some old script already added by hand. If you'd like it on fresher data, run `sudo ./backup.sh` first.

#### 15. GENERIC. Release it

The migrations travel with the module. In chapter 16's step 6, send the folder together with the module:

```sh
ssh nwn@GAME 'rm -rf incoming/migrations'
scp -r migrations nwn@GAME:incoming/
```

The first line clears what an earlier rehearsal left, so the folder on the game host is exactly the one in your
repository. Then release as usual, with `sudo ./release.sh`. When a release brings migrations, the script does
this, in order:

1. compares the folder with the ledger, and stops if a file that ran was changed or is missing;
2. makes the backup, as always;
3. rehearses the waiting files on a copy of that backup, and stops if they fail there;
4. stops the game, applies them to the live database, puts the new module in place, and starts the game.

Up to step 4 the game keeps running, so if the release stops there, your players never noticed. The output tells
you what happened at each step:

```
3 applied, 1 waiting
  waiting: 0004-bank-gold-index.sql
backup made: backups/20261126-142612 (16K)
rehearsing on a copy of backups/20261126-142612, in a throwaway mariadb:11.8 with no network
applying 0004-bank-gold-index.sql
applied 1, 3 were already applied
rehearsal passed: 3 tables in the copy afterwards; the copy is removed
game stopped
applying 0004-bank-gold-index.sql
applied 1, 3 were already applied
installed home/modules/mymodule.mod
game started
the game is healthy again
```

Afterwards the game folder keeps a copy of the folder in `~/game/migrations`, so `./migrate.sh status` there tells
you where the live database stands.

The migrations run while the game is stopped, so no script is halfway through using a table while it changes, and
they run before the new module starts, so the module never meets a table it doesn't expect.

#### 16. GENERIC. When a migration fails

Most failures are caught by the rehearsal, and then nothing has changed at all. The release says
`release stopped before anything changed`, and you fix the file and try again. A file that didn't work never ran,
so you may edit it freely.

Rarely, a file works on the copy and fails on the live database, because something changed since the backup. Then
the script stops at that file, puts the old module's game back up, and tells you which backup it made just before.
The ledger is still honest: the failed file isn't in it, and nothing after it ran.

It's worth knowing what a failed file leaves behind, because MariaDB treats two kinds of change differently:

- **Changes to rows** (`INSERT`, `UPDATE`, `DELETE`) are undone when the file fails, as long as they come after the
  file's last change to a table.
- **Changes to tables** (`CREATE`, `ALTER`, `DROP`) can't be undone. They take effect at once, and so do any row
  changes before them in the same file.

So a file that made a table and then failed leaves the table behind. That is exactly why every file should be safe
to run twice: once you fix the mistake, the next run makes nothing twice and carries on. On the test, a file that
made a table, added a row and then failed left the table, empty, and the corrected file ran cleanly over it.

#### 17. GENERIC. Going back

`sudo ./release.sh --undo` puts the old module back, as in chapter 16. It doesn't change the database back, and
it says so, naming the migrations that release applied and the backup made just before.

Usually that's fine. A migration that only adds tables and columns leaves the old module working. If you do need
the database back as it was:

```sh
ssh nwn@GAME 'cd game && ls -1d backups/2* | tail -3'
ssh -t nwn@GAME 'cd game && sudo ./restore-db.sh backups/20261126-142612'
```

It asks you to type `restore`, because everything stored since that backup is lost: every gold piece earned, every
quest finished since. Then it stops the game, empties the game's database, loads the backup and starts the game
again. On the test that took 3 seconds. The ledger comes back with the tables, so `./migrate.sh status` afterwards
lists the undone files as waiting again, which is exactly the truth. Your next release runs them again, as
always.

Please think twice before this step on a world with players, and if you can, take a fresh `sudo ./backup.sh` first,
so even the restore can be undone.

#### 18. GENERIC. How it fits with Coolify and the nightly backup

- **Coolify doesn't run migrations, on purpose.** Its **Restart** and **Deploy** remake the containers with the
  same module, so there's nothing new to migrate. Migrations go with releases, and releases go through
  `release.sh`, which finds the containers by name whichever of Compose or Coolify started them. Nothing about
  migrations goes into Coolify's settings.
- **The nightly dump carries the ledger.** A restore from any night brings back the tables and the list of files
  they've had, together, so the two never disagree.
- **The rehearsal uses the newest backup.** During a release that's the one made a moment earlier. By hand it's
  last night's, unless you name another with `BACKUP=backups/...`.
- **A copy needs room.** The throwaway database lives on the game host while it runs, and needs about as much disk
  and memory as your live one. For a small world that's nothing; for a big one, check `df -h` and `free -h` once.

#### 19. LAYONARA-ONLY. Dated names, rollback files and big rehearsals

Our files are named by date rather than number, and the biggest changes come with a rollback file and a rehearsal
script of their own that compares every table. Both grew out of one large rework of our housing. For a new world,
numbered files and the rehearsal in step 14 cover the same ground. Add rollback files when a change is too big to
undo by restoring a backup.

### The agent playbook

If you work with an AI agent, [`playbooks/05-database-tier2.md`](../playbooks/05-database-tier2.md) has these
steps in a fixed shape it can follow. An agent can write migrations, check them and rehearse them on copies as
often as it likes. Applying them to the live database happens inside a release, which is always your yes, and a
restore is always yours alone.

### Lessons

- **A file that ran is history.** The checksum check exists because editing an applied file is such an easy,
  well-meant thing to do, and it silently does nothing to the database. The script stops instead, and says to add
  a new file.
- **Table changes don't roll back.** I first wrapped each file in a plain transaction, expecting a failed file to
  leave no trace. The test showed that a `CREATE TABLE` ends the transaction, and a row added after it stayed. The
  script now keeps autocommit off for the whole file, which catches those rows, and step 16 says plainly what
  still can't be undone.
- **Rehearse on real data.** A migration that works on an empty database can still fail on yours: a duplicate, an
  old hand-made column. The rehearsal uses your own backup for that reason, and on the test it caught the failure
  in step 16 before the game was stopped.
- **Make the first migration describe what is already there.** Starting the folder with the tables you already
  have, written so they can run twice, means the folder alone can build your whole database. That is what lets us
  build our test database from the same files on every run.

### Tested

On 2026-11-26, on two fresh Hetzner cloud servers of the smallest shared type, with `nwnxee/unified:ed79330`,
MariaDB 11.8 and Ubuntu 26.04. First on the game host in the state tier 1 leaves it (game, database, the example
module from chapter 6 and the nightly backup):

- `status`, `rehearse` and `apply` of the two example migrations, then `apply` again (`nothing to apply`);
- an applied file changed by one comment line: `status` and `apply` refused, and a new file waiting beside it was
  not run; an applied file removed: refused; a misnamed file: reported and ignored;
- a failing file that made a table, added a row, then failed: the table left, empty, not recorded, and nothing
  after it run; the corrected file then ran over it. A failing file of row changes only: every change undone;
- releases with migrations through the new `release.sh`: one refused before the backup because an applied file was
  missing, the game untouched; one with a new migration, 22 seconds in all and the game healthy after; one whose
  migration failed on the copy, refused with the game untouched; one whose migration passed on the copy and failed
  on the live database (made to, for the test), with the old game back up, healthy, and the ledger unchanged;
- `release.sh --undo` after a release with a migration: the note naming it and the backup before;
- `restore-db.sh`: refused without the typed word and for a folder that isn't a backup; then a restore of the
  backup from before two migrations, 3 seconds, with tables, index and ledger as they were, and `status` listing
  the two as waiting; `apply` then brought them back;
- the nightly timer's dump containing the ledger's rows;
- two copies of `migrate.sh` at once (the second refused), and `apply` with the database stopped (refused).

Then all over again with the game moved into Coolify 4.7.5 on a second server, as chapter 4's tier 2 does it, the
database administrator's password nowhere in Coolify:

- a release of migrations only (23 seconds) and one of a module with a new migration (17 seconds), both healthy
  after and the service `running:healthy` in Coolify;
- a changed applied file refusing a release before its backup; a migration failing on the copy refusing one with
  the game untouched; the corrected file then released;
- `release.sh --undo` naming the migration and the backup before; `restore-db.sh` of that backup (2 seconds), the
  ledger back as it was and the undone file waiting again; `apply` then bringing it back;
- the nightly timer's service dumping the ledger with all its rows, and a Coolify **Restart** of the service
  leaving the ledger as it was, with nothing waiting.

Not tested: a database larger than a few tables (the rehearsal's time and room grow with it), migrations with
stored procedures or triggers, and a release with players online.

## Tier 3. The game and everything around it, through the database

### What you learn

By tier 3 your game has neighbours: a website where players look things up, a bot, reports for the staff, perhaps
an operations API. They all want two things from the game. They want to **ask it to do something** ("give this
character the item they bought on the website", "tell everyone the bank closes in five minutes"), and they want to
**read what it knows** without slowing it down or being able to break it.

The game is not easy to call. A script can't listen for requests, and NWNX's web client only reaches out over
HTTPS, so it can't call a service on your private network. What both sides can reach is the database. This section
uses it for three small patterns that have carried a lot of weight for us:

- a **work queue**: a table where outside services add jobs, and the game picks each one up, does it, and writes
  the outcome back, with a claim that makes sure two games, or one game restarting, never do a job twice;
- **revision counters**: one number per kind of data, which whoever changes that data adds one to, so anyone
  holding a copy knows when to reload without reading everything again;
- a **read-only account** for websites, bots and reports, with exactly the rights it needs, reachable only from
  your private network, and kept in step with your tables by a timer.

When you're done, you'll have:

- two new migrations, `work_queue` and `revisions`, released with tier 2's `release.sh`;
- three small scripts in your module: the poller, its functions, and one example job;
- the database published on the game host's private address, and nowhere else;
- a read-only account for the control host, refused on every write, on every other database, and from anywhere
  but its own address;
- an account for a website that may add jobs to the queue and do nothing else;
- a timer that gives the readers every new table within ten minutes, minus the columns you keep private.

**Time:** about forty minutes, most of it reading. On the test, the release that made both tables and brought the
poller took 32 seconds, rehearsal included, and a job added from outside ran in the game 4 seconds later.

### What Layonara does

- **Queues as tables.** Bug reports typed in the game go into a queue table, and our operations API files each one
  and writes the issue number back. Furniture moved on the website goes into another, and the game does the moving,
  because only the game may change what a container holds. Each queue has a `status` column, and the game claims
  a job with one `UPDATE ... WHERE status = 'queued'` and checks that exactly one row changed.
- **Each queue is its own table,** with columns made for its job. The template here is one general table; when one
  kind of job grows columns of its own, give it a table of its own too.
- **Revision counters, polled every 30 seconds.** Housing has a `rev` that the website adds one to whenever it
  changes a house, and the game reloads what changed. Some of these are bumped by database triggers, so no writer
  can forget.
- **A read-only account for looking into problems.** Our issue watcher, which looks into bug reports with an AI
  agent, reads the game's database through an account that may only `SELECT`, may only log in from one machine on
  our private network, and never sees columns named like a password, an email or an address. A timer every ten
  minutes keeps its rights in step with new tables. The script here is written the same way.
- **The database is published on the private address only,** for the operations API and the bot on the control
  host, a millisecond away.

### The human playbook

You need tier 2 of this chapter (migrations and `release.sh`), chapter 1's private network, and your module
repository from chapter 6. Commands use `GAME` for the game host's public address, `10.77.0.2` for its private
address and `10.77.0.1` for the control host's, as in chapter 1.

The files: [`templates/module/database/`](../templates/module/database) for the module (two migrations and three
scripts), [`templates/game/compose.db-private.yaml`](../templates/game/compose.db-private.yaml) and
[`templates/game/db-accounts.sh`](../templates/game/db-accounts.sh) with its timer for the game host.

#### 20. GENERIC. Why a table, and not a call

It helps to see why this works before doing it. Each side does what it's good at:

- **The outside service writes a row** and goes on with its day. It doesn't wait for the game, and it doesn't need
  the game to be up. If the game is restarting, the row simply waits.
- **The game looks every few seconds**, claims a row, does the work inside the world, where only it can, and writes
  down how it went.
- **The row is the record.** Anyone can see what was asked, by whom, when it ran and what came of it. When a player
  says "I bought it on the website and never got it", the answer is one `SELECT` away.

The hard part of any queue is making sure a job runs once, not twice and not never. Step 25 shows how the claim
does that, and what I did to try to break it.

#### 21. GENERIC. Add the two tables as migrations

Both tables come as ordinary tier 2 migrations. Copy them into your module's `migrations` folder under the next
two free numbers; if your last one is `0002`, that's:

```sh
cp templates/module/database/work-queue.sql ~/mymodule/migrations/0003-work-queue.sql
cp templates/module/database/revisions.sql ~/mymodule/migrations/0004-revisions.sql
```

`work_queue` has one row per job:

| Column | What it holds |
|---|---|
| `kind`, `args` | what to do: a job of kind `announce` runs the script `wq_announce` with `args` |
| `added_by` | who asked, for you to read later |
| `status` | `queued`, then `claimed` while a game does it, then `done` or `failed` |
| `claimed_by`, `claim`, `claimed_at`, `attempts` | who is doing it, since when, and how many tries so far |
| `result`, `done_at` | how it went, in words, and when |

`revisions` has one row per kind of data that something else keeps a copy of, starting with `server`, which the
game bumps each time it starts.

They'll go out with the module in step 22's release.

#### 22. ADAPT. Add the poller to your module

Change: your `OnModuleLoad` script, by one line.

The NWScript side is three small files. Copy them next to your other scripts:

```sh
cp templates/module/database/*.nss ~/mymodule/src/nss/
```

| File | What it does |
|---|---|
| `inc_queue.nss` | the functions: claim a job, finish it, put stale claims back, bump a revision |
| `db_poll.nss` | runs every 10 seconds: any revision that changed, then waiting jobs |
| `wq_announce.nss` | an example job: tells everyone online what `args` says |

They need only NWNX's SQL plugin, whose `nwnx_sql.nss` is already in your module from chapter 6. Start the poller
from your `OnModuleLoad` script, chapter 6's `mod_load.nss`, by adding this line at the end of `main`:

```c
    ExecuteScript("db_poll");
```

Then release the module and the migrations together, as in tier 2's step 15: the migrations folder and the new
`.mod` in `~/incoming`, and `sudo ./release.sh`. The migrations run while the game is stopped, so the new module
finds its tables waiting. The game's log then says:

```
mod_load: recorded this start in the database
db_poll: started as demo 468329b9-fa42-44f6-9a73-b3238532e944
```

`demo` is the module's name, and the long number a fresh id for this start of the game, so you can tell starts
apart in `claimed_by`.

#### 23. GENERIC. Send the game a job

As the game's own account, on the game host:

```sh
ssh nwn@GAME
cd game
docker compose exec mariadb sh -c 'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"'
```

```sql
INSERT INTO work_queue (kind, args, added_by) VALUES ('announce', 'The bank closes in five minutes', 'me');
```

Wait ten seconds, then:

```sql
SELECT id, kind, status, attempts, result FROM work_queue;
```

```
id  kind      status  attempts  result
1   announce  done    1         told 0 online
```

Everyone online saw the message, and the game's log has `wq_announce: job 1: The bank closes in five minutes`.
Try a kind the game doesn't know, `('nosuch', '', 'me')`: it comes back `failed`, with the result
`this game has no script wq_nosuch`. Nothing is lost silently.

(In Coolify, `docker compose exec mariadb` becomes `docker exec -it mariadb-<the service's id>`.)

#### 24. ADAPT. Write your own kind of job

Change: everything in the script; keep its first two and last lines.

A kind is a script named `wq_<kind>`, at most 13 letters after the `wq_`. Copy `wq_announce.nss` and change the
middle. It gets the job through three script parameters and must finish the job itself:

```c
#include "inc_queue"

void main()
{
    int nId = StringToInt(GetScriptParam("id"));
    string sClaim = GetScriptParam("claim");
    string sArgs = GetScriptParam("args");
    // ... do the work ...
    Queue_Finish(nId, sClaim, TRUE, "what happened, in words");
}
```

Three rules keep it honest:

- **Finish within the lease, two minutes.** A job may finish later than its script, for example after a
  `DelayCommand`. But a claim older than two minutes is taken for a game that stopped, and the job goes back in the
  queue.
- **Read the parameters into variables first,** as above. A `GetScriptParam` written inside a `DelayCommand` is read
  when the delay ends, and by then it's empty. I made exactly this mistake while testing, and the next step shows
  what happened.
- **Make the work safe to repeat.** A job runs again if the game stopped before finishing it. When the work is in
  the database, do it and `Queue_Finish` in one transaction (`NWNX_SQL_ExecuteQuery("START TRANSACTION")`, the work,
  the finish, `COMMIT`), so the two happen together or not at all. When it's in the world, giving an item for
  example, check first whether it was already done, perhaps by giving the item a tag with the job's number.

Write `args` as JSON when a job needs more than one thing; NWScript reads it with `JsonParse`.

#### 25. GENERIC. How the claim keeps a job to once

The claim is one statement:

```sql
UPDATE work_queue SET status = 'claimed', claim = ?, claimed_by = ?, claimed_at = NOW(), attempts = attempts + 1
 WHERE status = 'queued' ORDER BY id LIMIT 1
```

The database changes one row at a time under a lock, so when two games run this at the same moment, one gets the
row and the other finds it no longer `queued` and takes the next. Each claim carries a fresh random id, and
`Queue_Finish` writes the outcome only `WHERE claim = ?`, so a game that lost its claim can't overwrite someone
else's result.

Each poll also puts claims older than the lease back in the queue, up to three tries; after the third the job ends
`failed` with `gave up: no game finished it in 3 tries`. That covers a game that stopped in the middle of a job.

I tried to break it, so you don't have to:

- **Two game servers on one database,** 200 jobs added at once: each ran exactly once, 100 on each server, none
  retried.
- **Four programs claiming as fast as they could,** 1,000 jobs: every one claimed exactly once.
- **A game killed in the middle of two jobs:** they stayed `claimed` for two minutes, went back in the queue, and
  the other server finished each once.
- **A job script that finished too late,** with the empty `GetScriptParam` from step 24: its finish was refused with
  `claim lost, outcome not written`, it went back twice more, and then ended `failed` after three tries. A mistake,
  but a visible one.

There is one honest limit. If a game finishes the work and stops in the instant before `Queue_Finish`, the job runs
a second time. That is why step 24 asks for work that is safe to repeat.

#### 26. ADAPT. Revision counters

Change: the names in `revisions`, and an `rv_<name>` script for each one the game should react to.

A website showing the server's settings, a bot listing who owns which house: each keeps a copy and wants to know
when it's out of date. Reading everything every minute works until it doesn't. A revision counter is a cheaper
question: "has the number changed since I last looked?"

- **Whoever changes the data adds one to its row**, in the same transaction as the change:
  `UPDATE revisions SET rev = rev + 1 WHERE name = 'settings'`. In the game, `Rev_Bump("settings")` does it.
- **Whoever keeps a copy reads one number** and reloads when it differs from the last one it saw:
  `SELECT rev FROM revisions WHERE name = 'settings'`. That costs almost nothing, so it can be asked often.
- **The game watches them too.** Every 10 seconds `db_poll` reads all of them, and for each that changed it runs
  `rv_<name>` if your module has one: write `rv_settings.nss` to reload settings when the website changes them.

Add a row for each new name in a migration: `INSERT IGNORE INTO revisions (name) VALUES ('settings');`.

On the test, a reader on the control host asking every two seconds saw `server` go up three seconds after the game
restarted, and both game servers ran their `rv_settings` within ten seconds of an outside change.

A reader that can't reach the database should keep its copy and ask again. A Coolify **Restart** of the game
restarts the database too, and my first test reader took the refused connection for a change.

#### 27. GENERIC. Open the database to the private network

Until now only the game could reach the database. The services on your control host need it too, and chapter 1's
step 14 is the way: publish it on the game host's private address, and nowhere else.

With plain Compose (tier 1), copy the new file:

```sh
scp templates/game/compose.db-private.yaml nwn@GAME:game/
```

and in `~/game/.env` add `:compose.db-private.yaml` to the end of the `COMPOSE_FILE` line, and a new line
`DB_PRIVATE_ADDRESS=10.77.0.2`. Then `docker compose up -d`. That remakes the database's container, and the game
restarts with it, so players are away for a few seconds: a quiet hour is kind.

In Coolify (chapter 4, tier 2), add these lines to the `mariadb` service in the service's compose file, under its
`volumes`, and redeploy:

```yaml
    ports:
      - "10.77.0.2:3306:3306"
```

Either way, check from the control host, and then from your own computer:

```sh
ssh nwn@CONTROL 'timeout 4 bash -c "</dev/tcp/10.77.0.2/3306" && echo open'
timeout 4 bash -c "</dev/tcp/GAME/3306" && echo open || echo closed
```

`open`, then `closed`. One thing changes with this: the game's own account, which can change anything in the
game's database, now answers your private network too, to anyone with its password. Keep that password for the
game alone, and give every other service a smaller account of its own, as the next steps do.

#### 28. GENERIC. A read-only account

[`templates/game/db-accounts.sh`](../templates/game/db-accounts.sh) makes accounts for outside services. Copy it to
the game host with its timer:

```sh
scp templates/game/db-accounts.sh templates/game/db-accounts-sync.service templates/game/db-accounts-sync.timer nwn@GAME:game/
```

Make a password and keep it in a file only you can read. Later it goes into the service's own settings, in Coolify
for a website or a bot:

```sh
umask 077; openssl rand -hex 16 > website.password
ssh nwn@GAME 'cd game && ./db-accounts.sh reader website 10.77.0.1' < website.password
```

`made website, which may log in from 10.77.0.1 only`. The password travels on the input, so it is never on a
command line, in your shell's history or in the server's list of processes. The script uses the database
administrator's password from `db.env` on the game host, so nothing new leaves that machine.

What `website` may do:

- **Read every table of the game's database.** Nothing else: no other database, not the database's own list of
  accounts.
- **Never write.** `INSERT`, `UPDATE`, `DELETE`, `CREATE`, `ALTER`, `DROP`, `TRUNCATE`, `GRANT` and
  `CREATE USER` were all refused on the test, every one.
- **Log in from `10.77.0.1` only.** The same account and password from the game host itself were refused, and so
  were they from a public address when I opened the port to the world for a minute to check. Two locks, then: the
  port isn't on the public address, and the account wouldn't let a public address in even if it were.
- **Five connections at most, ten seconds per query.** A sixth connection is refused, and a query running longer
  is stopped, so a slow report can't hold up the game. `MAX_CONNECTIONS` and `MAX_SECONDS` change them.

`./db-accounts.sh show website` lists its rights. Make one account per service, each with its own password, so you
can take one away without touching the others: `./db-accounts.sh drop website`.

#### 29. ADAPT. Keep its rights in step, and keep private columns private

Change: `DENY_COLUMNS`, for your own private columns.

Readers get their rights through a role called `game_reader`, and `./db-accounts.sh sync` brings that role in step
with the tables: every table, and on a table with a private column, every other column. A column is private when
its name ends in `ip`, `ip_address`, `cdkey`, `public_cdkey`, `password`, `passwd`, `token`, `secret`, `email` or
`api_key`. If your tables have private columns named otherwise, add their names to the `DENY_COLUMNS` line at the top
of the script.

Switch on the timer, so a table added by a release can be read within ten minutes without anyone remembering. Its
first run is straight away:

```sh
ssh nwn@GAME 'cd game && sudo cp db-accounts-sync.service db-accounts-sync.timer /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now db-accounts-sync.timer'
```

`./db-accounts.sh sync --dry-run` shows what it would change, and after a release you can run `./db-accounts.sh sync`
yourself instead of waiting. On the test, a release added a table with `email`, `last_ip` and `public_cdkey`
columns. The timer's next run granted the other three columns and nothing more. When a column named `host_ip` later
appeared in a table the readers could read whole, `sync` took the whole-table right back and granted the other
columns instead.

#### 30. ADAPT. An account that may only add jobs

Change: which columns it may write, if your queue has more.

A website that sends jobs to the game needs to write to the queue, and to nothing else:

```sh
umask 077; openssl rand -hex 16 > webqueue.password
ssh nwn@GAME 'cd game && ./db-accounts.sh queue webqueue 10.77.0.1' < webqueue.password
```

`webqueue` may add rows to `work_queue`, setting only `kind`, `args` and `added_by`, and read that table to see how
its jobs went. It can't set a job's `status`, change or delete a row, or read any other table; all of that was
refused on the test. The website can ask; only the game decides what happened.

#### 31. GENERIC. With Coolify

Everything above works the same when the game runs in Coolify. The scripts find the database by its Compose service
name, the administrator's password stays in `~/game/db.env` and never goes into Coolify, and the accounts live in the
database's own folder, so a redeploy keeps them. On the test, the switch from plain Compose to Coolify kept every
account and right as it was.

#### 32. LAYONARA-ONLY. A table per queue, and a second database

Our queues each have a table of their own, with columns made for the job: a furniture move knows the house and both
containers. One general table, as here, is the right start; give a kind of job its own table once it needs columns
of its own. Our operations API also keeps a second database of its own beside the game's, for data no script in the
game needs to see.

### The agent playbook

If you work with an AI agent, [`playbooks/05-database-tier3.md`](../playbooks/05-database-tier3.md) has these
steps in a fixed shape it can follow. An agent can write job scripts, migrations and rehearsals, and read through a
read-only account. Opening the database to the private network, and making or removing an account, are your yes.

### Lessons

- **Tables travel where calls can't.** A script can't listen for requests, NWNX's web client reaches out only over
  HTTPS, and a website shouldn't wait on the game. A row both can reach gets around all three, and leaves a record.
- **One statement claims.** A claim that reads first and writes second lets two pollers take the same row. One
  `UPDATE ... WHERE status = 'queued' LIMIT 1`, and checking that it changed one row, leaves the database to decide.
- **Every claim has a deadline.** A game stops sometimes, mid-job. Without a lease the job would wait forever; with
  it, the job goes back, and after three tries it says so instead of trying forever.
- **`DelayCommand` reads its arguments late (2026-11-26).** My first slow test job passed `GetScriptParam("claim")`
  straight into a `DelayCommand`. It was read twenty seconds later, empty, and the claim check refused the finish.
  The check turned a silent mistake into a logged one.
- **A reader that can't read hasn't seen a change.** Treat an error as "ask again", never as "reload".
- **Bind accounts to an address.** A password can leak, a port can be opened by mistake. An account that only
  answers from one private address needs both to go wrong at once.

### Tested

On 2026-11-26, on two fresh Hetzner cloud servers of the smallest shared type in the state tier 2 of this chapter
leaves them (game host with the game, its database, chapter 6's example module and the nightly backup; control host
with Coolify 4.7.5; WireGuard between them), with `nwnxee/unified:ed79330`, MariaDB 11.8 and Ubuntu 26.04:

- the two migrations and a module with the three scripts in one `release.sh` release, 32 seconds, rehearsal included;
  later releases adding a table and a revision name;
- jobs added as the game's account and as the queue account from the control host, run within ten seconds; a kind
  without a script ending `failed`;
- 200 jobs with two game servers polling one database, each run once; 1,000 claims raced by four programs, each
  once; a game killed in the middle of two jobs, which the other server finished once after the lease; a finish
  with a wrong claim refused, and the job failed after three tries;
- a revision bumped by the game at start and seen by a reader on the control host three seconds later; revisions
  bumped from outside, and both game servers running `rv_settings`;
- the database reachable from the control host on the private address and closed on the public one;
- the read-only account: reads allowed; every write, table change, account change and other database refused; a
  sixth connection refused; a 15-second query stopped at 10; refused from the game host's private address and from
  a public address with the port opened for the test;
- `sync` after a release with private columns, by hand and by its timer; the whole-table right taken back when a
  private column appeared; `show` and `drop` refusing the game's account and the administrator;
- the queue account allowed to add a job and refused everything else;
- all of it again with the game moved into Coolify, the `ports` lines in its compose file and no administrator
  password in Coolify or in either container: a release with a migration (35 seconds), `sync`, the accounts, a
  job, a Coolify **Restart** with the revision seen from the control host, and a reboot of the game host, after
  which the database was back on the private address only and the timer active;
- the whole agent playbook and its roll back, run as written on the game host restored to how it was before tier 3,
  with the module built by hand instead of by nasher. That run found three faults in the playbook and the script,
  all fixed and the steps run again.

Not tested: a queue with thousands of jobs waiting (the poller does ten every ten seconds; change `JOBS_PER_POLL`),
jobs with players online, and readers on a busy database.
