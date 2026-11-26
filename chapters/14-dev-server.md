# Chapter 14. A dev server

**Status:** tier 2 is written and tested. Tier 1 doesn't need a dev server. Tier 3 (loading a build from Discord, a
dev server with custom content of its own) is not written yet.

A **dev server** is a game of its own, away from the live one, where builders and scripters try things: a pull
request's module before anyone has reviewed it, a script half-written, an area that might not work yet. It isn't
chapter 6's staging copy. Staging holds the next release, checked, and plays with yesterday's world so you can try it
before players do. The dev server is a workbench: it holds whatever someone is working on today, and nobody minds
when it breaks.

## Tier 1

Nothing to do here. One person building alone has the toolset, a local server, and chapter 6's compile check, and
that is plenty. Skip this chapter.

## Tier 2. A workbench for builders, with a safe copy of the world

### What you learn

Whether you need a dev server at all, and if you do, how to run one on your control host that your builders can
load their own pull requests onto, that has a copy of your world's database with your players' private details
taken out, and that nobody else can find or reach.

This part is **optional**, and I'd say so plainly. You want one when:

- two or more people build or script, and they want to see their work on a real server with NWNX and a database
  before it is reviewed, without waiting for a release, and without each running a server at home;
- or someone wants to test against real-looking data (a hundred characters, a year of quests) and not an empty
  database.

If you build alone, or your team is happy with the staging copy and a server at home, you lose nothing by skipping
it. Staging already gives you a place to try the next release.

When you're done, you'll have:

- a second game on the control host, with its own folders, its own database and its own passwords, never in the
  game's public server list;
- its port open to your builders' addresses only;
- one command on a builder's computer that puts a pull request's build on it (`load-build.sh pr 12`), and one that
  takes it back;
- one command on the control host that gives it a copy of the live database, with account names, CD keys,
  addresses and passwords scrubbed out first, which refuses to run when it meets a private-looking column it hasn't
  been told about;
- the live game untouched by all of it: the dev server never writes to the game host, and reads only last night's
  backup.

**Time:** about an hour. On the test, loading a build took 11 to 14 seconds and a copy of the database 23 seconds,
both on a cx23.

You need chapter 3 (Coolify on the control host, with the game host reached over the private network), chapter 6's
compile check, and chapter 12's nightly backup. Chapter 5's tables are what gets copied.

### What Layonara does

- **A dev server on the control machine,** as its own Docker Compose service in Coolify, with its own MariaDB. It is
  never in the public server list, and has passwords of its own.
- **Its settings are made from the live game's** by a small script that reads them over Coolify's API, keeps the
  game and plugin settings, drops everything that talks to the outside world (webhooks, metrics), sets the dev
  values, and checks that no outside-facing credential slipped through. It shows a dry run first.
- **Files reach it only through a key with a forced command:** a dozen small verbs (put the module, put a hak,
  roll back, restart, status, the steps of a data copy), each checking what it is given: the file's first bytes, its
  size, its name.
- **Builders load it from Discord.** `/dev load` with a pull request's number asks our operations API to start a
  workflow that builds that pull request and delivers it. `/dev rollback` puts the previous one back, and a status
  page says which commit is loaded.
- **A copy of the live data on request.** The newest nightly dump, refused if it is more than 36 hours old, goes in
  with the big log tables left out: about half the dump, and of no use for testing.
- **Custom content of its own.** A second NWSync host serves the dev server's haks and falls back to the live ones
  for everything else, so a builder can try a new hak without touching what players download. That is tier 3.

### The human playbook

The files are in [`templates/dev`](../templates/dev): `dev.yaml` (the Coolify service), `dev.sh` (what a builder's
key may do), `load-build.sh` (a builder's side of it), `copy-db.sh` with `scrub.list.example` (the copy), and
`send-dump.sh` (the game host's side of the copy).

The examples use `CONTROL` and `GAME` for the two machines' public addresses, `10.77.0.1` and `10.77.0.2` for their
private ones from chapter 1, and `nwn` as the deploy user.

#### 1. GENERIC. Know what keeps it apart from live

Four things, and each step below is one of them:

- **Another machine.** The dev server runs on the control host, so a builder's script that loops forever slows
  the dev server and nothing else.
- **Its own database,** filled only by `copy-db.sh`, from a scrubbed copy. Nothing on the dev server can reach the
  live database: it isn't published on any port, and the dev server's settings don't name it.
- **Its own passwords,** so one that leaks opens nothing live.
- **Out of sight:** unlisted, with its port open only to your builders.

#### 2. ADAPT. Folders and scripts on the control host

Change: the paths, if your deploy user isn't `nwn`.

```sh
ssh nwn@CONTROL 'mkdir -p ~/dev/home/modules ~/dev/db ~/dev/logs'
scp templates/dev/dev.sh templates/dev/copy-db.sh templates/dev/scrub.list.example nwn@CONTROL:dev/
```

Making the folders yourself matters a little: a folder Docker makes for a missing path belongs to root, and then
`dev.sh`, which runs as `nwn`, can't put a module in it.

`~/dev` isn't in chapter 12's backup of the control host, and doesn't need to be. Everything in it can be made again
from live and from GitHub.

#### 3. ADAPT. The service in Coolify

Change: the paths in the file, as in step 2; the plugins, to match live.

In Coolify, make a project called `dev` and add a resource: **Docker Compose**, on the control host itself (the
server Coolify calls `localhost`), and paste [`templates/dev/dev.yaml`](../templates/dev/dev.yaml). In
**Environment variables**, **Developer View**:

```
NWNX_IMAGE=nwnxee/unified:ed79330
NWN_MODULE=mymodule
NWN_SERVERNAME=My server (dev)
NWN_MAXCLIENTS=8
NWN_PLAYERPASSWORD=a password for your builders
NWN_DMPASSWORD=a new one, not the live one
NWN_ADMINPASSWORD=a new one, not the live one
NWNX_SQL_PASSWORD=a new one, not the live one
NWNX_SQL_SKIP=n
NWNX_SQL_TYPE=mysql
NWNX_SQL_DATABASE=nwn
NWNX_SQL_USERNAME=nwn
NWNX_UTIL_SKIP=n
```

plus the `NWNX_..._SKIP=n` lines your live game has, except for plugins that send things out, such as a webhook to
your Discord. A builder's test that posts "the dragon is dead!" to your players' channel is a lovely story, once.
Then **Deploy**.

Two settings are in the file and not here, on purpose. `NWN_PUBLICSERVER` is fixed at `0` in `dev.yaml`, so the dev
server stays unlisted even if someone later pastes `NWN_PUBLICSERVER=1` into Coolify: I tried, and the container
still got `0`. And the services are named `dev-nwserver` and `dev-mariadb`, so no script looking for the live game
can find this one.

The game keeps restarting until it has a module, which step 5 gives it. That's expected.

#### 4. GENERIC. Open the port to your builders only

The dev game publishes UDP 5121 on the control host. Docker opens published ports past `ufw` (chapter 1, step 6), so,
as with Coolify's own ports in chapter 3, the provider's firewall is the one that counts. On the test, before the
firewall rule, the dev server answered every machine on the internet.

In your provider's firewall for the control host, add a rule: UDP 5121, from each builder's address. With
`nwn-status.py` from chapter 4, the difference is easy to see:

```sh
templates/game/nwn-status.py CONTROL 5121
```

```
CONTROL port 5121 is up: module mymodule, room for 8 players
```

from a builder's address, and `no answer from CONTROL port 5121` from anywhere else.

If your builders' addresses change too often for a list, open it to everyone and lean on the player password; the
server is still unlisted. That's a fair trade for a small team, and it is yours to make.

#### 5. GENERIC. A key that can only load builds

Each builder gets a key that can do three things on the control host: load a build, roll back, and say what's
loaded. On the builder's computer:

```sh
ssh-keygen -t ed25519 -N '' -C dev-loader-yourname -f ~/.ssh/mymodule-dev
```

and you, on the control host, add its public half with `dev.sh` as its forced command:

```sh
{ printf 'command="/home/nwn/dev/dev.sh \\"$SSH_ORIGINAL_COMMAND\\"",restrict '; cat mymodule-dev.pub; } \
  | ssh nwn@CONTROL 'cat >> ~/.ssh/authorized_keys'
```

It's the same pattern as chapter 6's staging key. `command=` runs `dev.sh` whatever the login asks for, and hands it
the request to check; `restrict` turns off the shell, port forwarding and file copying. On the test the key was
refused a shell command, a label with spaces, a file that isn't a module, a port forward and `scp`.

Now load main's newest build, from the builder's computer, with `gh` logged in to your module's repository:

```sh
export GH_REPO=you/mymodule CONTROL=nwn@CONTROL
templates/dev/load-build.sh main
```

```
compile check run 45853543956 built mymodule.mod for bfc572a
received main-bfc572a: 39126 bytes, sha256 b2861ae5...
dev server is healthy with main-bfc572a
```

`load-build.sh` builds nothing. It finds the compile check that passed for that commit (chapter 6, step 8),
downloads the module it built, and sends it. So the dev server runs exactly the file the check looked at.

#### 6. GENERIC. Load a pull request, and take it back

```sh
templates/dev/load-build.sh pr 1
```

```
compile check run 45853968566 built mymodule.mod for e1b67dc
received pr-1-e1b67dc: 39192 bytes, sha256 b2c9aada...
dev server is healthy with pr-1-e1b67dc
```

The label says where the build came from: the pull request and its newest commit. Connect with your game client to
`CONTROL`, port 5121, with the builders' password, and try it. When you're done, or if it was a bad idea:

```sh
templates/dev/load-build.sh rollback
templates/dev/load-build.sh status
```

```
dev server is healthy with main-bfc572a again
loaded:      2026-11-26T16:00:10Z main-bfc572a sha256 b2861ae5...
before it:   2026-11-26T16:00:31Z pr-1-e1b67dc sha256 b2c9aada...
database:    never copied from live
game:        healthy
```

`dev.sh` keeps the build before the current one, and a second rollback swaps them back. If a new build doesn't
become healthy (the game crashes twice in a row, or five minutes pass), it puts the one before back by itself and
says so. On the test, a broken module was replaced by the build before it 47 seconds after it arrived, without
anyone stepping in.

A word about whose pull requests you load. A build is code, running on your control host with NWNX's powers. Your
own team's, fine. A pull request from someone you don't know is worth reading before it goes anywhere near a server.

A pull request's compile check keeps its module for 14 days. For an older one, re-run the check from the pull
request's page and load it again.

#### 7. ADAPT. Write down what is private

Change: everything in this file; it describes your tables.

Before your players' data goes anywhere near the dev server, write down what in it is private. On the control host:

```sh
cp ~/dev/scrub.list.example ~/dev/scrub.list
```

and edit `scrub.list`: one line per column, the table, the column, and what to do with it. For a world with an
accounts table and a chat log, mine was:

```
players     cdkey          blank
players     ip_address     null
players     account        pseudonym
players     password_hash  null
players     discord_id     null
characters  account        pseudonym
chat_log    *              empty
```

`blank` and `null` empty a column. `pseudonym` gives each account name a stand-in like `p7689221f25b5`, the same
everywhere in one copy, so a character still belongs to its player and a join still joins; the secret that makes
them is new each time and never kept, so the next copy's stand-ins are different and nobody can work back from them.
`empty` takes every row from a table. And `keep` is for a column whose name looks private and isn't.

What counts as private is your call, and I'd lean towards more. A good rule: anything that would let a builder find
out who a player is, or reach them outside the game. Character names and levels are the game itself; account names,
CD keys, addresses, passwords, emails and Discord ids are the person.

The demo database from chapters 5 and 6 has nothing private in it, so for that one an empty `scrub.list` is right,
and `copy-db.sh` agrees. The test used a made-up `players` table, below.

#### 8. GENERIC. A key that can only fetch the dump

The copy needs last night's dump from the game host, so the control host gets a key that can fetch that and nothing
else. On the control host, make the key and learn the game host's own key over the private network:

```sh
ssh nwn@CONTROL "ssh-keygen -q -t ed25519 -N '' -C dev-copy-db -f ~/.ssh/dev-copy-db"
ssh nwn@CONTROL 'ssh-keyscan -t ed25519 10.77.0.2 >> ~/.ssh/known_hosts; ssh-keygen -lf ~/.ssh/known_hosts | grep 10.77.0.2'
ssh nwn@GAME 'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub'
```

The last two lines should show the same `SHA256:...` fingerprint: that's how you know the control host is talking to
your game host and not something pretending to be it. Then put `send-dump.sh` on the game host, beside the backups,
and bind the key to it:

```sh
scp templates/dev/send-dump.sh nwn@GAME:game/
ssh nwn@CONTROL 'cat ~/.ssh/dev-copy-db.pub' \
  | { printf 'command="/home/nwn/game/send-dump.sh",from="10.77.0.1",restrict '; cat; } \
  | ssh nwn@GAME 'cat >> ~/.ssh/authorized_keys'
```

`from=` means the key works only from the control host's private address. On the test, the same key from the public
address was refused, and asking it to run `rm -rf ~` got... the dump. `send-dump.sh` reads one file, and refuses if
the newest backup is more than 36 hours old, because then the nightly backup has stopped and that's worth knowing
first.

#### 9. GENERIC. Copy the database

On the control host:

```sh
cd ~/dev && GAME=nwn@10.77.0.2 ./copy-db.sh --yes
```

```
live backup 20261126-155824 loaded into a throwaway database
  players.cdkey: blank, 3 rows changed, 0 left
  players.ip_address: null, 3 rows changed, 0 left
  players.account: pseudonym, 3 rows changed, 0 left
  players.password_hash: null, 2 rows changed, 0 left
  players.discord_id: null, 2 rows changed, 0 left
  characters.account: pseudonym, 4 rows changed, 0 left
  chat_log.*: empty, 2 rows changed, 0 left
scrubbed with 7 rules from scrub.list, every rule checked
dev game stopped
dev database filled from live backup 20261126-155824, scrubbed
dev server is healthy on the copied database
```

Without `--yes` it only tells you what it would do: a copy replaces everything in the dev database, so what builders
made there is gone, and the dev game restarts.

What happens underneath is the part I care most about. The dump goes straight from the game host into a throwaway
MariaDB that has **no network** and keeps its data **in memory only**, so the unscrubbed copy never lands on the
control host's disk. There `copy-db.sh` checks your rules against the real tables, applies them, and checks each one
again from the data: after `blank`, it counts the rows that still hold a value, and anything but 0 stops it. Only
then does it touch the dev database. The throwaway database is deleted when the script ends, however it ends.

It stops, and the dev server keeps the database it had, when:

- a rule names a table or column that isn't there (on the test, a typo, `ip_adress`);
- **a column whose name looks private has no rule.** On the test I added a column `last_login_ip` to live, the way
  a migration would. The next copy stopped with `players.last_login_ip looks private and has no rule in scrub.list`.
  One line in `scrub.list` later, it went through. This is the check I'd least like to be without: the day someone
  adds an email column, the copy asks you instead of passing it on;
- the dump is old, incomplete, or the game host can't be reached.

Look for yourself, too. Your players' data deserves a second pair of eyes, even when the first pair is a script:

```sh
ssh nwn@CONTROL 'docker exec $(docker ps -q --filter label=com.docker.compose.service=dev-mariadb) \
  sh -c "mariadb -u\$MARIADB_USER -p\$MARIADB_PASSWORD \$MARIADB_DATABASE -t -e \"SELECT * FROM players LIMIT 5\""'
```

On the test that showed every account as a `p...` stand-in and the other private columns empty, the characters
still joined to their players, and a search of the control host's whole disk found none of the original values.

And at any time, without copying anything, `copy-db.sh` can hold the dev database up against your rules:

```sh
ssh nwn@CONTROL 'cd dev && ./copy-db.sh --check'
```

```
  players.cdkey (blank): 0 left
  players.ip_address (null): 0 left
  ...
the dev database keeps every rule
```

On the test I put one real-looking CD key back by hand, and `--check` found it: `players.cdkey (blank): 1 left`,
`the dev database breaks a rule`.

Characters aren't copied. The character vault's folders are named after players' accounts, so it would undo the
scrub; builders make characters of their own on the dev server.

Run a copy when builders want fresh data, not on a timer. Once a week is plenty, and asking first is kind: it
throws away whatever they were testing.

#### 10. GENERIC. Builders, day to day

What a builder needs from you: the control host's address, the builders' password, their address in the firewall,
and their key in `authorized_keys`. What they do:

```sh
templates/dev/load-build.sh pr 42     # try my change
templates/dev/load-build.sh status    # what's on there now?
templates/dev/load-build.sh rollback  # put it back
```

There's one dev server and several builders, so it helps to say in your team's chat what you've loaded. When
someone leaves the team, delete their key's line from `~/.ssh/authorized_keys` (it ends in the comment they gave it)
and take their address out of the firewall.

#### 11. LAYONARA-ONLY. Discord, and custom content

Our builders load the dev server from Discord, through the operations API (chapter 9) and a workflow, and a
builder can claim it for an hour so two people don't load over each other. And the dev server has its own NWSync
host for haks that aren't live yet. Both are tier 3: worth it with many builders, overkill with two.

### The agent playbook

If you work with an AI agent, [`playbooks/14-dev-server-tier2.md`](../playbooks/14-dev-server-tier2.md) has these
steps in a fixed shape. It stops and asks before it opens the firewall, before it adds a key to either machine, and
before every database copy; it never writes `scrub.list` for you.

### Lessons

- **A scrub list goes stale the day someone adds a column.** A list of what to blank is only as good as its last
  update, and the person adding `last_login_ip` in a migration is rarely thinking about the dev server. So the copy
  looks at every column's name and stops at one that looks private and has no rule. I'd rather answer a question
  once a month than find an address on a builders' server.
- **Check the result, not the command.** An `UPDATE` that matched no rows looks just like one that worked. After each
  rule, `copy-db.sh` counts what is left, and only 0 lets it go on.
- **Scrub somewhere private.** If the raw dump went into the dev database first and were fixed there, the dev
  server would hold real data for a few seconds, and for good if the script died halfway. A database with no
  network, in memory, that is thrown away, has no such moment.
- **Give fixed settings no setting.** The dev server must never be listed, so `dev.yaml` writes `0` instead of
  reading a setting someone could change. It cost one line.
- **Load what the check built.** A builder's own build may differ from the check's (another nasher, an uncommitted
  file). Loading the check's file means "it works on dev" is about the commit everyone can see.

### Tested

On 2026-11-26, with Coolify 4.7.5, `nwnxee/unified:ed79330`, MariaDB 11.8, nasher 1.2.2 and Ubuntu 26.04 on two
cx23s (a game host in tier 1's state with the nightly backup, and a control host from chapter 3, joined by
WireGuard), and a private throwaway module repository with chapter 6's compile check:

- the dev service from `dev.yaml` deployed by Coolify on the control host; restarting until its first module, as
  expected; `NWN_PUBLICSERVER=1` set in Coolify and the container still getting `0`; the server absent from the
  game's public server list (333 servers listed that day);
- the port: answering every address before the firewall rule; with a Hetzner firewall allowing UDP 5121 from one
  address only, answering that address (my own computer, standing in for a builder) and silent to another
  machine; the dev database published on no port;
- `load-build.sh main`, `pr 1` (a pull request that changed the module's log line, seen in the dev server's log),
  `rollback` twice and `status`; the loaded file's checksum the same as the compile check's artifact; loads took 11
  to 14 seconds;
- the forced-command key refusing a shell command, a bad label, a file that isn't a module, a port forward and `scp`;
- a broken module (a real module's first 2,000 bytes): the build before it put back by itself, the dev server
  healthy again, in 47 seconds (5 minutes 26 before `dev.sh` learned to count crashes); a rollback after that
  refused, as there was nothing older left;
- the dump key: refused from the public address, sending the dump whatever it was asked to run, refusing a backup
  40 hours old;
- `copy-db.sh` with a made-up `players`, `characters` and `chat_log` (three accounts with CD keys, addresses,
  password hashes and Discord ids): refusing without `--yes`, without `scrub.list`, with rules missing, with a typo
  in a rule, with a new unlisted column added on live, and with the game host unreachable, each time leaving the dev
  database as it was; then a full copy in 23 seconds, with the scrubbed columns checked by hand in the dev
  database, the joins intact, new stand-ins on the next copy, and no original value anywhere on the control host's
  disk (a `grep` of the dev database's files and every text file);
- the live game throughout: the same container start time and health before and after, answering its status query,
  its database still holding the real values;
- `copy-db.sh --check` passing on the copy, and failing on a CD key I put back by hand;
- this chapter's agent playbook, as written, after taking everything down with its roll back. Its first Verify
  check was a shell one-liner that broke on its own quoting; it became `copy-db.sh --check`, and the run passed.

The Coolify service was made through Coolify's API, which does what those dashboard pages do. Not tested: a game
client connecting (the status query answered instead), a module with haks on the dev server, and a large database
(the throwaway database keeps everything in memory, so a dump bigger than about a third of the control host's memory
needs a machine with more).
