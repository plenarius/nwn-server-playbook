# Chapter 12. Backups and restore

**Status:** tiers 1 and 2 are written and tested. Tier 1 is a nightly backup on the machine and a copy fetched to
your computer; tier 2, further down, sends encrypted backups to another company's storage, out of reach of a
broken-into server, and restores them onto a fresh machine. Tier 3 (the character vault's history in git, and a
daily watch) is not written yet.

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

## Tier 2. Off-site, encrypted, and out of reach

### What you learn

How to send every night's backup to another machine, encrypted, in a way that a broken-into server can add to and
can't take away from. And, as in tier 1, the half that matters more: how to get it all back onto a new machine,
and how to know it came back right.

When you're done, you'll have:

- a backup of the game host, and of the control host with Coolify, sent every night to a storage machine at
  another company, encrypted before it leaves;
- a key on each server that can only add to its own backups: it can't destroy the history, can't read anyone
  else's, and can't fill the disk;
- old backups tidied from your own computer, the one place allowed to delete, with a check that stops if anything
  went missing in between;
- the passphrase and key kept where you, or whoever comes after you, can find them;
- a restore onto a fresh machine, done once, with every file and table checked against the original.

**Time:** about an hour, the restore drill included. On the test, a backup of the example game took 2 seconds, and
once a fresh machine was prepared with chapter 1, it took 76 seconds to get from there to the restored game
answering.

### What Layonara does

- **borg, one repository per machine,** each encrypted (`repokey-blake2`) with its own passphrase, sent over SSH to
  a storage machine at a different provider from the machines it backs up.
- **The backup key is locked on the receiving side** to `borg serve --append-only --storage-quota ...
  --restrict-to-repository ...`: it can add to that one repository, it has a size limit, and that's all.
- **Pruning goes through a second key,** locked on the receiving machine to a small wrapper that runs one fixed
  policy: 14 daily, 8 weekly and 12 monthly archives. The passphrase travels on standard input, so the receiving
  machine never stores it, and the wrapper refuses to remove more than 40 archives in one go.
- **The storage machine backs itself up** to a Hetzner Storage Box, so the backups have a second home too.
- **A daily watch** on the storage machine looks only at file times and sizes, so it needs no passphrase, and
  alerts when a repository is 36 hours stale or at 80% of its quota.
- **Every passphrase is in a password manager,** in a vault meant for whoever comes after us.
- **The first backups** were about 8 GB per machine before borg, and 2 to 8 GB after its compression and
  deduplication. From then on each night adds only what changed.

### The human playbook

The files for this section are in [`templates/backup`](../templates/backup):
[`borg-backup.sh`](../templates/backup/borg-backup.sh) with its config
[`borg.conf.example`](../templates/backup/borg.conf.example), a hook that dumps the game's database
([`hooks/10-game-db.sh`](../templates/backup/hooks/10-game-db.sh)), the nightly timer
([`borg-backup.service`](../templates/backup/borg-backup.service),
[`borg-backup.timer`](../templates/backup/borg-backup.timer)), the tidy for your computer
([`borg-prune.sh`](../templates/backup/borg-prune.sh)), and for the control host
[`borg.conf.control.example`](../templates/backup/borg.conf.control.example) and
[`hooks/10-coolify-db.sh`](../templates/backup/hooks/10-coolify-db.sh). One more,
[`borg-wind-back.sh`](../templates/backup/borg-wind-back.sh), is for a bad day and step 17.

The examples use `GAME` for the game host, `CONTROL` for the control host, `STORAGE` for the storage machine and
`NEWSERVER` for a fresh machine you restore to.

#### 8. GENERIC. Know what borg adds

[borg](https://www.borgbackup.org/) is a backup program built for exactly this. Three things about it matter here:

- **It encrypts on your server.** The storage machine only ever sees scrambled data, so it doesn't have to be one
  you trust with your players' characters.
- **It deduplicates.** It cuts every file into pieces and stores each piece once. The second night's backup only
  sends the pieces that changed: on the test, 22 kB of a 921 kB backup.
- **It can be told to only add.** In *append-only* mode the storage side never changes or removes anything already
  written. A delete still looks as if it worked, but it only adds a note that says "this is gone", and the note can
  be undone. Space is only really freed by a key that is allowed to, and in this guide that key lives on your own
  computer.

Tier 1's nightly backup stays as it is: it's quick to restore from, and it's on the machine. borg is the copy
elsewhere, and replaces the `rsync` of step 4. It makes its own database dump, in plain SQL without a date inside,
because a compressed file looks entirely new to borg every night, and a plain one is mostly the same as yesterday.

#### 9. ADAPT. Rent the storage

Change: where the storage lives.

You want space at **a different company** from your servers, reachable by SSH, with borg on it. Two kinds work:

- **A storage box,** such as Hetzner's Storage Box: disk space with SSH and borg, and nothing else to look after.
  It offers several borg versions; you pick yours with `BORG_REMOTE_PATH` (for example `borg-1.4`), and it listens
  on port 23. We use one for the storage machine's own backups, with the same kind of locked keys as below.
- **A small machine of your own** at another provider, prepared with chapter 1. This is what I tested with: a
  second throwaway Hetzner cloud machine stood in for the storage box. On it, make an account that owns the
  backups and nothing else:

  ```sh
  sudo apt-get install -y borgbackup
  sudo adduser --disabled-password --gecos "" borg
  sudo -u borg install -d -m 700 /home/borg/repos /home/borg/.ssh
  sudo -u borg install -m 600 /dev/null /home/borg/.ssh/authorized_keys
  ```

Our tests ran borg 1.4.4 on both ends, the version in Ubuntu 26.04. Keep the two ends on the same major version.

#### 10. GENERIC. Give the game host its key and passphrase

Copy the files to the game host:

```sh
scp -r templates/backup nwn@GAME:backup
```

Then on the game host, install borg and the script, and make the three secrets it lives on: a config, an SSH key
and a passphrase. All of them go into `/etc/nwn-borg`, which only root can read:

```sh
sudo apt-get install -y borgbackup
cd ~/backup
sudo install -m 755 borg-backup.sh /usr/local/sbin/nwn-borg-backup
sudo install -d -m 700 /etc/nwn-borg /etc/nwn-borg/hooks.d
sudo install -m 700 hooks/10-game-db.sh /etc/nwn-borg/hooks.d/
sudo install -m 600 borg.conf.example /etc/nwn-borg/borg.conf
sudo ssh-keygen -q -t ed25519 -N '' -C borg-game -f /etc/nwn-borg/ssh-key
sudo sh -c 'umask 077; openssl rand -base64 32 > /etc/nwn-borg/passphrase'
sudo sh -c 'ssh-keyscan -t ed25519 STORAGE > /etc/nwn-borg/known_hosts'
sudo ssh-keygen -lf /etc/nwn-borg/known_hosts
```

Edit `/etc/nwn-borg/borg.conf`: put your storage's address in `REPO`, and check the paths. They are tier 1's list
from step 1, plus the folder the database hook writes into. If your deploy user isn't `nwn`, change the paths.

The last command prints the storage machine's fingerprint. If you can, compare it with what the storage shows
(on your own machine, `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`; for a storage box, its provider's
page). From now on the script refuses to talk to anything with a different one.

#### 11. GENERIC. Lock the key on the storage side

Print the game host's public key, which is safe to copy around:

```sh
sudo cat /etc/nwn-borg/ssh-key.pub
```

On the storage side, add one line to `authorized_keys` (`/home/borg/.ssh/authorized_keys` on a machine of your
own), all on one line, with that key at the end:

```
command="borg serve --append-only --restrict-to-repository /home/borg/repos/game --storage-quota 20G",restrict ssh-ed25519 AAAA... borg-game
```

That line is the whole lock, so here is what each part does:

- `command="borg serve ..."`: whatever the game host asks for, the storage runs this and only this. No shell.
- `--append-only`: it can add, and nothing it does removes anything already written.
- `--restrict-to-repository`: this one repository and no other, so a broken-into game host can't reach the
  control host's backups.
- `--storage-quota 20G`: it can't fill the disk. Give it room to grow, a few times your first backup.
- `restrict`: no port forwarding, no terminal, none of SSH's other tricks.

On a storage box the path is relative to its home folder; check its documentation for the exact form.

#### 12. GENERIC. Make the repository, and keep the key and passphrase safe

```sh
sudo nwn-borg-backup borg init --encryption=repokey-blake2
```

`nwn-borg-backup borg ...` runs any borg command with this machine's settings, so you never have to type the
repository's address or the passphrase.

Now the most important minute of this chapter. The backups can be read with the **passphrase** and the
**key**, and with nothing else. `repokey` keeps the key inside the repository, locked with the passphrase, and the
passphrase lives on the game host. If the game host is lost, the passphrase goes with it, unless you've kept a
copy. **Without the passphrase, the backups are noise. Nobody can open them, not even borg's authors.** On the
test, a wrong passphrase got exactly this, and nothing else:

```
Passphrase supplied in BORG_PASSPHRASE, by BORG_PASSCOMMAND, or via BORG_PASSPHRASE_FD is incorrect.
```

So, from your own computer, print both and put them into your password manager, in one entry:

```sh
ssh -t nwn@GAME 'sudo cat /etc/nwn-borg/passphrase'
ssh -t nwn@GAME 'sudo nwn-borg-backup borg key export'
```

The first is a line of 44 characters, the second a block that starts with `BORG_KEY`. The exported key is your
spare in case the copy inside the repository is ever damaged. You'll need it together with the passphrase. If you
like paper, `borg key export --paper` prints a version you can type back in.

Mind who's looking at your screen while these are on it. And I'd do one more thing: tell one other person where
that entry is. Ours is in a vault meant for whoever comes after us.

#### 13. GENERIC. The first backup, and the second

```sh
sudo nwn-borg-backup
```

It runs the hooks first (here, a fresh database dump), checks every path in the config is there, sends the
backup, and ends with `backup made:` and the archive's name. The statistics above that line show the sizes. Run it
again a minute later, and look at the line `This archive:`: the last number, *Deduplicated size*, is what this
night really added. On the test it was 22 kB, for a backup of 921 kB.

```sh
sudo nwn-borg-backup borg list
```

lists the archives, newest last.

If anything goes wrong, a hook failing, a path missing, borg unable to reach the storage, no archive is made, the
script says why, and it exits with an error. A path that has moved is treated as an error on purpose: otherwise
every backup afterwards would have a hole in it that nobody notices.

#### 14. GENERIC. Make it nightly, and hear about failures

```sh
cd ~/backup
sudo cp borg-backup.service borg-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now borg-backup.timer
systemctl list-timers borg-backup.timer
```

It runs a little after 09:30 UTC, half an hour after tier 1's backup. To see how last night went:
`journalctl -u borg-backup.service`.

If you have a Discord channel for alerts (chapter 13 sets one up), put its webhook address in
`/etc/nwn-borg/alert-webhook`, and the script posts there whenever a backup fails. Check it's heard:

```sh
sudo sh -c 'umask 077; cat > /etc/nwn-borg/alert-webhook'    # paste the address, then Ctrl-D
sudo nwn-borg-backup --test-alert
```

This tells you when a backup fails. It can't tell you when the backups stop altogether, say because the machine is
gone. For that, the tidy in step 16 tells you the newest backup's age, and chapter 13's outside watch can do it
every day.

#### 15. ADAPT. The control host, and Coolify

Change: add the folders of anything else that lives only on your control host.

The control host gets the same treatment with its own key, its own passphrase and its own repository, so that
neither machine can reach the other's backups. Follow steps 10 to 14 on it, with three differences:

- the config is `borg.conf.control.example`, and the hook is `hooks/10-coolify-db.sh`;
- the key's comment is `borg-control`, and its line on the storage side names `/home/borg/repos/control`;
- the password manager entry is a second one, for the control host.

What it keeps is everything Coolify needs to come back: a fresh dump of Coolify's own database, in the format
Coolify's restore instructions use, and `/data/coolify`, which holds Coolify's settings, the SSH keys it reaches
your servers with, and the files of every resource. Inside `/data/coolify/source/.env` is `APP_KEY`, the key
Coolify encrypts its secrets with. **The database dump is no use without it**, which is why the whole folder goes
along. Put the `APP_KEY` line into the control host's password manager entry as well.

#### 16. GENERIC. Prove the lock holds

This is worth five minutes, because it shows what a burglar on your game host could do. On the game host, try to
destroy the history:

```sh
sudo nwn-borg-backup borg delete --force
```

borg refuses: `... is in append-only mode`. Then try something sneakier, deleting one archive:

```sh
sudo nwn-borg-backup borg list --short
sudo nwn-borg-backup borg delete ::FIRST-ARCHIVE-NAME
sudo nwn-borg-backup borg compact
sudo nwn-borg-backup borg list --short
```

This one *looks* as if it worked: no error, and the archive is gone from the list. That's borg's append-only mode
as designed. Nothing was removed on the storage side, only a note was added, and on the test the repository grew
a little instead of shrinking. `compact` ran without a word and freed nothing. Step 18 shows how to undo it, and
I'd do that now, so you've done it once on a calm day.

Two more refusals you can see: asking the storage to run a command of your own (`sudo ssh -i /etc/nwn-borg/ssh-key
borg@STORAGE rm -rf repos` gets borg's usage message, and nothing is removed), and asking for another repository
(`Repository path not allowed`). And with the
quota set low for a moment, a backup that didn't fit was refused with `The storage quota ... has been exceeded`,
and no archive was made.

#### 17. GENERIC. Tidy from your own computer

Somebody has to remove old archives, or the repository grows until the quota stops it. That somebody needs a key
that may delete, and the safest home for that key is your own computer, which no player connects to.

On your computer, install borg (`sudo apt install borgbackup`, or `brew install borgbackup` on a Mac), make a key
just for this, and add its line to the storage side:

```sh
ssh-keygen -t ed25519 -C borg-tidy -f ~/.ssh/borg-tidy
```

```
command="borg serve --restrict-to-path /home/borg/repos",restrict ssh-ed25519 AAAA... borg-tidy
```

No `--append-only`: this is the key that may delete, in every repository under that folder. Then, once a month or
so:

```sh
export BORG_RSH="ssh -i ~/.ssh/borg-tidy"
templates/backup/borg-prune.sh ssh://borg@STORAGE/./repos/game
```

It asks for that repository's passphrase (from your password manager), and prints how many archives there are,
how old the newest is, and which archives the policy would remove: it keeps 14 daily, 8 weekly and 12 monthly,
as we do. Nothing is removed until you add `--apply`:

```sh
templates/backup/borg-prune.sh ssh://borg@STORAGE/./repos/game --apply
```

Then it removes those archives and frees their space, and refuses if that would be more than 40 at once. Do the
same for `repos/control`.

The script also remembers which archives it saw last time. Between two tidies your servers can only ever add, so
if one it saw before has gone, someone deleted it. Then it stops, before freeing anything, and says which:

```
STOP: these archives were there last time and are gone now:
  game-2026-11-26T1424
Nothing was removed.
```

That stop matters more than it looks. A deletion in append-only mode can be undone only until a key that may
delete frees the space, and freeing space is exactly what a tidy does. The check makes sure the tidy never makes a
burglar's work permanent.

#### 18. GENERIC. If an archive has gone missing

Take a breath: in append-only mode, nothing is really lost yet. Don't run any tidy until you've finished this.

On a storage machine of your own, as the `borg` account, list the repository's *transactions*, each write to it,
with its time:

```sh
sudo install -m 755 borg-wind-back.sh /usr/local/bin/borg-wind-back
sudo -u borg borg-wind-back /home/borg/repos/game
```

Find the last one from before the trouble. The archives' times help: on the test the three backups were
transactions 5, 9 and 13, and the deletion was 17. Then wind back to it:

```sh
sudo -u borg borg-wind-back /home/borg/repos/game 13 --apply
```

It first makes a hard-linked copy beside the repository, which costs almost no space, so a wrong number can be
put right. Then it removes everything written after that transaction. The archive is back.

Every machine that saw the repository after the deletion now remembers a newer state, and borg will refuse with
`Cache, or information obtained from the security directory is newer than repository - this is either an attack
or unsafe`. That's borg looking after you. On each of them (the game host, and your computer), clear what it
remembers:

```sh
sudo nwn-borg-backup borg delete --cache-only
sudo sh -c 'rm /root/.config/borg/security/*/manifest-timestamp'
```

On your computer, the same without `sudo` and with the repository's address after `--cache-only`, and the folder
is `~/.config/borg/security`. When the copy is no longer needed, remove `/home/borg/repos/game.before-13`.

If the deletion came from a game host you no longer trust, the honest next step is chapter 1 and step 19: a new
machine, and that host's key removed from `authorized_keys`.

On a storage box there's no shell to run the script in. The same file operations are possible through its SFTP
access, but I haven't tested that.

#### 19. GENERIC. The restore drill: everything back on a fresh machine

This is tier 1's step 6 again, from borg this time. I did it on the test onto a machine that had never seen the
game, while the old one was still running, and compared everything afterwards. Do the same once, and again every
few months.

1. Rent a machine and prepare it (chapter 1). Copy the game's files, the backup files and the module to it:

   ```sh
   scp -r templates/game nwn@NEWSERVER:game
   scp -r templates/backup nwn@NEWSERVER:backup
   scp ~/mymodule/mymodule.mod nwn@NEWSERVER:
   ```

2. On the new machine, do step 10 again, all but the line that makes a passphrase. Instead, give it the one from
   your password manager:

   ```sh
   sudo bash -c 'umask 077; read -r -s -p "passphrase: " p; echo "$p" > /etc/nwn-borg/passphrase'
   ```

3. Add the new machine's key on the storage side as in step 11, with the same repository. If the old machine is
   gone for good, remove its line there.

4. Bring the files back. borg stores paths without the leading `/`, so extracting from `/` puts everything where
   it was:

   ```sh
   sudo nwn-borg-backup borg list --short
   cd / && sudo nwn-borg-backup borg extract --list ::THE-ARCHIVE
   ```

   The list shows the characters, the settings, `.env` and `db.env`, and the database dump in
   `/var/backups/nwn-borg`.

5. Start the database alone, wait until it is healthy, load the dump, and start everything:

   ```sh
   cd ~/game
   sudo mkdir -p home/modules && sudo cp ~/mymodule.mod home/modules/
   docker compose up -d mariadb
   docker compose ps
   sudo cat /var/backups/nwn-borg/game-db.sql | docker compose exec -T mariadb sh -c 'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"'
   docker compose up -d
   ```

6. Check that it really is your world. On both machines, if you still have the old one, or against numbers you
   wrote down before:

   ```sh
   sudo sha256sum home/servervault/*/*.bic home/settings.tml home/cryptographic_secret .env db.env
   docker compose exec -T mariadb sh -c 'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" -e "CHECKSUM TABLE YOUR_TABLE"'
   ```

   On the test, every checksum matched, the table's rows and its checksum matched, and the game answered with its
   module (`templates/game/nwn-status.py NEWSERVER`). The one difference was expected: the example module adds a
   row to `server_starts` each time it starts, and the new machine had started once.

7. Install both nightly timers: tier 1's (step 3) and borg's (step 14). The new machine carries on in the same
   repository, so the history continues.

From the first `scp` to the game answering took 76 seconds on the test.

#### 20. ADAPT. Restoring Coolify

Change: the Coolify version, to the one you backed up.

Coolify's own [restore instructions](https://coolify.io/docs/core/backup-and-recovery/instance-restore) are
short, and the backup from step 15 has everything they ask for. On a fresh control host, prepared with chapter 1
and with borg set up as in step 19, items 2 and 3:

1. Install the same version of Coolify as on the old control host (chapter 3), and check its dashboard opens.

2. Bring the backup back **into a side folder**, not over the fresh install, and check what came back:

   ```sh
   sudo nwn-borg-backup borg list --short
   sudo mkdir -m 700 /root/restore
   sudo bash -c 'cd /root/restore && nwn-borg-backup borg extract ::THE-ARCHIVE'
   sudo bash -c 'sha256sum /root/restore/data/coolify/source/.env /root/restore/data/coolify/ssh/keys/*'
   ```

   If you still have the old machine, the checksums should match its `/data/coolify/source/.env` and keys.

3. Then Coolify's own steps, with the files from the backup. Stop Coolify (its database keeps running), put the
   old `APP_KEY` in place, load the dump, bring back the SSH keys, and run the installer again:

   ```sh
   sudo bash -s <<'EOF'
   R=/root/restore
   docker stop coolify coolify-redis
   sed -i "s|^APP_KEY=.*|$(grep '^APP_KEY=' $R/data/coolify/source/.env)|" /data/coolify/source/.env
   docker exec -i coolify-db pg_restore --clean --if-exists --exit-on-error --no-acl --no-owner --username=coolify --dbname=coolify < $R/var/backups/nwn-borg/coolify-db.dmp
   rm -f /data/coolify/ssh/keys/*
   cp -a $R/data/coolify/ssh/keys/. /data/coolify/ssh/keys/
   curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash -s 4.7.5
   EOF
   ```

   Only `APP_KEY` changes in `.env`; the fresh install's other values, such as its database password, stay.

4. Coolify reaches its own machine with its old key now. Give that key to your deploy user, as in chapter 3's
   step 5:

   ```sh
   for k in $(sudo sh -c 'ls /data/coolify/ssh/keys/ssh_key@* | grep -v lock'); do sudo ssh-keygen -y -f $k | sed 's/$/ coolify/' >> ~/.ssh/authorized_keys; done
   ```

   Your game host already knows that key, so Coolify can reach it as before, once the new control host has the
   old one's place in the private network (chapter 1, tier 2).

5. Log in with your **old** dashboard password, open **Servers**, **localhost**, and **Validate**.

On the test, the restored Coolify had the project made before the backup, the old API token worked, and
localhost validated, which needs the private key that only the old `APP_KEY` can decrypt. Coolify's own guide
says what this doesn't cover: the data of the applications and databases it runs. In this guide that's the game,
and the game's data is in the game host's backup.

#### 21. LAYONARA-ONLY. A prune wrapper on the receiving side

Our storage machine is one of ours, so the tidy runs there and not on anyone's computer: each server sends its
passphrase on standard input to a second key, locked to a wrapper that runs one fixed policy and refuses large
removals. It runs every week without anyone remembering to. It needs a storage machine that can run a script,
which a storage box can't, and it takes more care to get right than the tidy above. Start with the tidy from your
computer; move to a wrapper if you find yourself forgetting.

### The agent playbook

If you work with an AI agent, [`playbooks/12-backups-tier2.md`](../playbooks/12-backups-tier2.md) has these steps
in a fixed shape it can follow. It never prints a passphrase or a key; it hands those to you to put in your
password manager, and waits until you have. Any `--apply`, any wind back and any restore over live data are
always your yes.

### Lessons

- **A delete in append-only mode looks like it worked.** We found this when we set up our storage box on
  2026-10-26: the locked key could delete an archive and run `compact`, without an error, and nothing was freed.
  The test for this section showed the same with borg 1.4.4. It's the design, and a good one, but it means the
  protection depends on whoever frees space looking first. That's why the tidy here remembers what it saw.
- **The passphrase is the backup.** Encryption on your side means nobody else can read your backups, and also
  that nobody can help you if the passphrase is lost. We keep every one in a password manager, in an entry meant
  for the person who comes after us.
- **One repository and one key per machine.** A broken-into machine can then reach its own backups and nothing
  else, and a mistake in one machine's config can't touch another's.
- **A restore isn't done until it's compared.** "The game started" isn't the same as "the game is the same". On
  our first borg backups, on 2026-10-25, a sample from each machine was restored and compared byte for byte; the
  drill here compares every file and table it can.
- **From my own test runs:** after a wind back, transaction numbers come round again, so the script that lists
  them shows only the ones still there; a quota under 10 MB is refused by borg itself; and a backup that hit the
  quota left its unfinished pieces behind until the next tidy freed them.

### Tested

On 2026-11-26, with borg 1.4.4 (the Ubuntu 26.04 package on the servers; the official standalone build of 1.4.4 on
my computer), MariaDB 11.8 and Coolify 4.7.5, on fresh Hetzner cloud machines of the smallest shared type: a game
host in tier 1's state, a control host with Coolify, a second machine as the stand-in for a storage box (an
account with only the `authorized_keys` lines above), and fresh machines for the restores.

- the setup of steps 9 to 12, and the key export and a wrong passphrase;
- a first backup and an incremental one (921 kB, then 22 kB more), and the control host's backup of Coolify;
- the nightly timer, moved for a moment to two minutes ahead: it fired and made an archive;
- failures: the database stopped (no archive, an alert), a path missing from the config (no archive), and a test
  alert, all received by a small local web receiver standing in for Discord;
- from the game host: deleting the repository (refused), deleting an archive, a prune and a compact (all appeared
  to work, nothing freed), a shell on the storage (refused), another repository (refused), and the quota (refused);
- winding back a deletion, by hand and with `borg-wind-back.sh`, and the archive back;
- the tidy from my computer: a look, a refusal when an archive had gone missing, a refusal above the limit, then a
  prune with space freed; and the game host's next backups working after it;
- **the restore drill** of step 19 onto a fresh machine: every file identical by SHA-256, the table identical by
  row count and checksum, and the game answering; then the new machine's nightly backup into the same repository,
  and the old machine refused once its key was removed;
- **Coolify's restore** of step 20 onto another fresh machine with Coolify 4.7.5: `.env` and the SSH key
  identical by SHA-256, the dump loaded, the project made before the backup there, the old API token and the old
  dashboard password working, localhost validated with the restored key, and the next nightly backup carrying on
  in the same repository.

Not tested: a real storage box (the stand-in had the same kind of locked keys), the wind back through a storage
box's SFTP access, `borg key import` from the exported key, a large world's backup, and the daily `crontab` or
reminder you'll want for the tidy.
