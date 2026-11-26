# Chapter 12. Backups and restore

**Status:** tier 1 is written and tested. Tier 2 (encrypted backups that a broken-into server can't delete, and an
alert when they stop) and tier 3 (the character vault's history in git) are not written yet.

## What you learn

How to back up the parts of your server that exist nowhere else, every night, without thinking about it. And the
half that matters more: how to get everything back.

When you're done, you'll have:

- a backup of the database, the characters and your settings, made every night by a timer;
- a script that never leaves a half-made backup behind and never replaces a good one with a bad one;
- a copy of those backups somewhere that isn't the server;
- the experience of having restored one, which is the only thing that turns a backup into something you can rely
  on.

**Time:** about twenty minutes, and most of that is the restore you do for practice. On the test, rebuilding the
whole game on a new, empty machine from a backup took 60 seconds once the machine itself was prepared.

## What Layonara does

- **A database dump every night,** on the game host, kept as seven dailies, four weeklies and three monthlies.
- **The characters every six hours.** Our players' character files go into a private git repository four times a
  day, so we have their history and not only the latest copy.
- **Everything, encrypted, to another machine every night,** and to a second provider. If one company has a bad
  day, the backups are at the other.
- **The receiving side only accepts additions.** The key a server uses to send its backup can add to the backups
  and cannot delete or change them. A server that is broken into can't destroy its own history.
- **A watcher complains** when the game host's backup is more than 36 hours old.
- **The passphrases are where a successor can find them,** in a password manager entry made for that day.

Tier 1 below is the first of those, done carefully, plus the copy elsewhere. It's a real backup. The rest are what
you add as more people come to depend on your world.

## The human playbook

Each step carries a label: GENERIC (the same for any server), ADAPT (works once you change the things it names) or
LAYONARA-ONLY (something we do that you probably shouldn't copy).

The files for this chapter are in `templates/game`: [`backup.sh`](../templates/game/backup.sh), and the two files
of a nightly timer, [`nwn-backup.service`](../templates/game/nwn-backup.service) and
[`nwn-backup.timer`](../templates/game/nwn-backup.timer).

### 1. GENERIC. Know what needs backing up, and what doesn't

Three things on your server exist nowhere else:

- **the database:** everything your module has stored (chapter 5);
- **the characters:** `home/servervault`, and with it `home/database`, the game's own small databases;
- **your settings:** `.env`, `db.env`, and two files the server made for itself, `home/settings.tml` and
  `home/cryptographic_secret`.

Everything else can be made again from somewhere: the module and the haks from your repositories (chapters 6 and
7), the images from the internet, the machine from chapter 1. That is the quiet reward for keeping things in git.
The backup stays small, and a restore is mostly steps you've already done once.

### 2. GENERIC. Make one backup by hand

If you copied `templates/game` before this chapter existed, copy the three new files first:

```sh
scp templates/game/backup.sh templates/game/nwn-backup.service templates/game/nwn-backup.timer nwn@SERVER:game/
```

Then, on the server:

```sh
cd ~/game
sudo ./backup.sh
ls -la backups/*/
```

You should see `backup made: backups/` followed by a date and time, and in that folder two files: `db.sql.gz`, the
database, and `files.tar.gz`, the characters and settings. The game keeps running the whole time.

The script is short, and I'd like you to read it, because its caution is the lesson of this chapter:

- it writes into a folder marked unfinished, and only gives the folder its real name when both files are complete;
- it checks that the database dump really ends where a dump should end;
- if anything fails, no new backup appears and nothing old is touched;
- it removes backups older than 14 days only after a new one has succeeded, and always keeps the newest three.

The backup holds your passwords, because it holds `.env` and `db.env`. The script makes it readable by you alone.
Treat every copy of it with the same care as the server itself.

### 3. GENERIC. Make it nightly

```sh
sudo cp nwn-backup.service nwn-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now nwn-backup.timer
systemctl list-timers nwn-backup.timer
```

The last command shows when it runs next: a little after 09:00 UTC each day. Pick an hour when your world is quiet
by editing the time in `nwn-backup.timer` before you copy it. If the machine happens to be off at that hour, the
backup runs when it comes back.

To see how last night went:

```sh
systemctl status nwn-backup.service
```

If your game folder isn't `/home/nwn/game`, change the two paths in `nwn-backup.service` first.

### 4. ADAPT. Get the backups off the machine

Change: where the second copy lives.

A backup that sits on the same machine as the thing it backs up protects you from mistakes, and from nothing else.
If the machine is lost, both are lost. So the backups need a second home.

The simplest second home is your own computer. This fetches whatever is new:

```sh
rsync -a nwn@SERVER:game/backups/ ~/nwn-backups/
```

Run it whenever you like, and better, let your computer run it every day. On Linux or macOS, `crontab -e` and a
line like this does it at noon:

```
0 12 * * * rsync -a nwn@SERVER:game/backups/ $HOME/nwn-backups/
```

This is the honest weak spot of tier 1: it depends on your computer being on, and nothing tells you when it stops
working. Glance into `~/nwn-backups` now and then. Tier 2 replaces this step with something that doesn't rely on
you.

### 5. GENERIC. Restore one, to look

Please don't skip this step. A backup you have never restored is a hope, not a backup.

This loads last night's database into a spare database beside the real one, counts something in both, and removes
the spare again. Nothing live is touched. On the server, in `~/game`:

```sh
b=$(ls -1d backups/2* | tail -1)
docker compose exec -T mariadb sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -e "CREATE DATABASE restore_check"'
zcat $b/db.sql.gz | docker compose exec -T mariadb sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" restore_check'
docker compose exec -T mariadb sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -e "SHOW TABLES FROM restore_check; DROP DATABASE restore_check"'
```

You should see your tables listed. With the example from chapter 6, that is `server_starts`. If you know a table
well, count its rows in both databases before the `DROP` and see that they agree.

And look inside the other file:

```sh
tar tzf $b/files.tar.gz | head
```

Your characters' folders should be in the list.

### 6. GENERIC. Know how to rebuild everything

This is the day the backup is for: the machine is gone, and you have a backup folder on your own computer. I did
exactly this on the test, onto a new empty machine, so the steps below are a record and not a theory.

1. Rent a machine and prepare it (chapter 1).
2. Copy the game's files and the backup to it, and the module (and haks, if you have them) from your repositories:

   ```sh
   scp -r templates/game nwn@NEWSERVER:game
   scp -r ~/nwn-backups/THE-BACKUP nwn@NEWSERVER:restore
   scp ~/mymodule/mymodule.mod nwn@NEWSERVER:
   ```

3. On the new machine, unpack the files. This brings back your settings, your passwords and the characters:

   ```sh
   cd ~/game
   sudo tar xzpf ~/restore/files.tar.gz
   sudo mkdir -p home/modules && sudo cp ~/mymodule.mod home/modules/
   ```

4. Start the database alone, wait until it is healthy, and load the dump:

   ```sh
   docker compose up -d mariadb
   docker compose ps
   zcat ~/restore/db.sql.gz | docker compose exec -T mariadb sh -c 'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"'
   ```

5. Start everything, and check as in chapters 4 and 5:

   ```sh
   docker compose up -d
   ```

6. Point your names at the new machine's address (chapter 2), and install the backup timer again (step 3).

Because the restored settings carry the same passwords, the new database is created with them, and the game logs in
as before. Because `cryptographic_secret` came back too, it is the same server as far as the game is concerned.

If you run custom content (chapter 7), put the haks and the talk table back in step 3 as well, and send the
download folder again.

### 7. LAYONARA-ONLY. Characters in git

Our character files go into a git repository every six hours. It gives us every character's history, not only last
night's copy. It also means a repository full of other people's characters, which has to be kept private and looked
after. For a new world, the nightly backup covers the characters well. Add the history when you find yourself
wishing for it.

## The agent playbook

If you work with an AI agent, [`playbooks/12-backups.md`](../playbooks/12-backups.md) has these same steps in a
fixed shape it can follow. An agent may make backups and check them freely. It restores only into a spare database,
and it asks you before anything that would write over live data.

## Lessons

These are the things that went wrong for us, written down so they don't have to go wrong for you. The dates are
when they happened to Layonara.

- **A failed backup must never replace a good one (2026-10-25).** Our nightly dump once couldn't reach the
  database, and the script didn't notice. It wrote a file 20 bytes long and called it the backup, and that file
  could take the place of the same day's good one. Since then the dump retries, checks its own size, and writes
  nothing at all when it isn't right. The script in this chapter is built around that one incident.
- **Two places, two companies.** Every machine of ours keeps its backups at a different provider from the one it
  runs at. A provider's bad day shouldn't be able to reach both.
- **Restore before you need to.** When we moved our backups to a different machine on 2026-11-07, the move wasn't
  called finished until a backup had been made, tidied and restored from the new place.
- **Write down where the keys are.** A backup that only one person can open is one accident away from being no
  backup. Ours are in a password manager, in an entry meant for the person who comes after.

## Tested

On 2026-11-18, on fresh Hetzner cloud servers of the smallest shared type that had been through chapters 1, 4, 5
and 6:

- a backup by hand, and what is inside both files;
- a backup while the database was stopped: an error, no new backup, nothing left behind, and the earlier backup
  untouched;
- the check for a complete dump, against a dump with its last lines cut off and against a file cut off in the
  middle;
- removing old backups: older than 14 days removed, and the newest three kept even when all were old;
- the nightly timer: installed, its next run listed, and the backup run through it;
- fetching the backups to another computer with `rsync`;
- the restore into a spare database, with the same row count as the live one;
- **a rebuild from nothing:** a second, empty server was prepared with chapter 1 and then rebuilt from a backup by
  the steps in step 6. It came up healthy in 60 seconds with the same database rows, a character file identical to
  the original by checksum, the same passwords, and the game answering.

Not tested: the daily line in `crontab`, a backup of a large database (the test's was tiny), and a restore after a
real disaster, which I hope neither of us ever gets to test.
