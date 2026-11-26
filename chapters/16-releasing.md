# Chapter 16. Day to day: releasing

**Status:** tiers 1 and 2 are written and tested. Tier 1 is a checklist and one script; tier 2, further down,
ties the staged releases of chapters 5, 6, 7 and 12 into one routine, with what to do when each step fails and what
a second person needs to run it. Tier 3 (a calendar of things that expire, and our full list of incidents) is not
written yet.

## What you learn

How to put a new version of your world in front of your players without holding your breath. Every piece already
exists in the earlier chapters. This one puts them in an order, as a checklist you can keep beside you, with a
small script that does the nervous part the same way every time.

When you're done, you'll have:

- a checklist for before, during and after a release;
- a check that catches a module using a plugin your server hasn't switched on;
- one command on the server that backs up, keeps the old files, swaps in the new ones and tells you how it went;
- one command that puts the old version back.

**Time:** the release itself took 9 seconds on the test, from the command to a healthy game. The checklist around
it is ten unhurried minutes.

## What Layonara does

- **A written order.** Our release steps are a page in the module's repository, written down after a release that
  went less smoothly than it should have. Nobody releases from memory.
- **Checks before, checks after.** Before: everything merged is green, and a tool confirms the live server has
  every plugin the new module uses. After: the same tool reads the server's start-up log, and someone tries the
  release's main new feature in the game.
- **Content first, then the module, then the switch.** New haks are published and their download list is rebuilt
  before the module that needs them goes live.
- **Players are warned.** A countdown in the game tells everyone when the server will restart.
- **Releases are frequent and small.** Six in ten days at the time of writing.

## The human playbook

Each step carries a label: GENERIC (the same for any server), ADAPT (works once you change the things it names) or
LAYONARA-ONLY (something we do that you probably shouldn't copy).

The files for this chapter are [`templates/game/release.sh`](../templates/game/release.sh), which runs on the
server, and [`templates/module/tools/check_plugins.py`](../templates/module/tools/check_plugins.py), which goes in
your module's repository. If you made your copies before this chapter existed:

```sh
scp templates/game/release.sh nwn@SERVER:game/
cp templates/module/tools/check_plugins.py ~/mymodule/tools/
```

The script uses the backup from chapter 12, so do that chapter first.

### The checklist

Keep this part. The steps below explain each line once; after that, the list is all you need.

**Before**

- [ ] Everything for this release is merged, and the check on `main` is green.
- [ ] The plugin check passes against the server.
- [ ] The NWNX version is the same in all three places.
- [ ] Players know when.

**During**

- [ ] If content changed: the download folder is published first.
- [ ] The new files are in `~/incoming` on the server.
- [ ] `sudo ./release.sh` says the game is healthy again.
- [ ] If settings changed: `docker compose up -d`.

**After**

- [ ] The status tool answers, and the log shows the module loaded without errors.
- [ ] I joined, and tried the thing this release is about.
- [ ] The release is tagged in git.
- [ ] Players know it's done, and what changed.

### 1. GENERIC. Merged and green

A release is whatever is on `main`. Look at the last check there:

```sh
cd ~/mymodule
gh run list --branch main --limit 1
```

It should say `completed` and `success`. If it doesn't, today is not the day, and that is a perfectly good outcome
for a checklist.

### 2. GENERIC. The plugin check

```sh
ssh nwn@SERVER 'grep -E "^NWNX_[A-Z0-9_]+_SKIP=" game/.env' | python3 tools/check_plugins.py src -
```

The first half asks the server which plugins it has switched on. It sends only those lines, and none of your
passwords. The second half reads your module's scripts and compares. You want to see `the server has every plugin
the module uses switched on`.

If it names a plugin instead, add that plugin's line to the server's `.env` (chapter 4, step 8). That is a settings
change, so remember the "if settings changed" line of the checklist.

This check exists because of the worst kind of release problem: one where nothing fails. A module that uses a
plugin the server hasn't switched on loads perfectly. It breaks later, in front of the first player who uses that
feature.

### 3. GENERIC. One NWNX version in three places

Three things have to agree on the NWNX version: the image your server runs, the image your check compiles against,
and the `nwnx_*.nss` files in your module.

```sh
ssh nwn@SERVER 'grep "^NWNX_IMAGE=" game/.env'
grep "NWNX_IMAGE:" .github/workflows/compile-check.yml
```

The two tags should be the same. The script files came from that version if you fetched them as chapter 6, step 5
shows. When you move to a newer NWNX (chapter 4, step 11), change all three in the same release.

### 4. ADAPT. Tell your players when

Change: where your players are.

Say it where they'll see it, and give a time. A restart takes seconds, but being dropped in the middle of a fight
without warning feels like much more. Give more notice for a big change than for a small one.

### 5. GENERIC. Publish content first, if it changed

If this release changes haks or the talk table, do chapter 7's step 11 up to and including the `rsync` of the
download folder. It adds files and changes nothing for the running game, so it can be done hours ahead.

### 6. GENERIC. Put the new files in `~/incoming`

The module that the check on `main` built is the one to release. Fetch it and send it:

```sh
cd ~/mymodule
RUN=$(gh run list --branch main --limit 1 --json databaseId -q '.[0].databaseId')
rm -rf /tmp/release && gh run download $RUN -n module -D /tmp/release
ssh nwn@SERVER 'mkdir -p ~/incoming'
scp /tmp/release/*.mod nwn@SERVER:incoming/
```

If content changed, send the haks and the talk table to the same place:

```sh
scp ~/myhaks/build/hak/*.hak ~/myhaks/build/tlk/*.tlk nwn@SERVER:incoming/
```

### 7. GENERIC. Release

On the server:

```sh
cd ~/game
sudo ./release.sh
```

It makes a backup first and stops if the backup fails. It keeps a copy of every file it is about to replace. Then
it stops the game, swaps the files, starts the game, and waits. The last line is the one to read: `the game is
healthy again`.

If your settings changed for this release, now is the moment for `docker compose up -d`.

### 8. GENERIC. Look, then join

From your own computer, the status tool from chapter 4:

```sh
templates/game/nwn-status.py SERVER
```

On the server, what the game said as it started:

```sh
docker compose logs --since 5m nwserver | grep -i -E "error|loaded plugin|Module loaded"
```

You want `Module loaded`, a `Loaded plugin` line for each plugin you expect, and no errors.

Then log in yourself and try the one thing this release was for. It takes a minute, and it is the only check that
looks at the game the way your players will.

### 9. GENERIC. Tag it

```sh
cd ~/mymodule
git tag -a v0.2 -m "What this release is, in a sentence"
git push origin v0.2
```

Do the same in your content repository if it changed. A tag costs nothing, and it answers the question you'll ask
six weeks from now: what exactly was live on that day?

Then tell your players it's done, and what's new.

### 10. GENERIC. When it goes wrong

If `release.sh` ends with `the game did not become healthy`, or the game is up but something is clearly broken:

```sh
sudo ./release.sh --undo
```

That puts back the files the release replaced and starts the game again. On the test, a module that couldn't load
was undone this way, and the earlier version was running again within seconds.

Two things to keep in mind when you're under that kind of pressure:

- **Go back first, understand later.** Your players get their evening back, and you get to read logs calmly.
- **The files go back; the database doesn't.** If a release changed what is stored in the database, the undo
  doesn't change it back. The backup that `release.sh` made a moment before is your way home (chapter 12, step 5),
  and that is exactly why it makes one.

### 11. LAYONARA-ONLY. The countdown and the release page

Our players get a countdown in the game before a restart, and our releases are started from a page that won't let
the steps run in the wrong order. Both are built on the pieces in tier 2. Until then, a message to your players and
this checklist do the same job by hand.

## The agent playbook

If you work with an AI agent, [`playbooks/16-releasing.md`](../playbooks/16-releasing.md) has these same steps in a
fixed shape it can follow. An agent can do every check, and it can prepare everything up to the release. The
release itself, the moment players are disconnected, is always your yes.

## Lessons

These are the things that went wrong for us, written down so they don't have to go wrong for you. The dates are
when they happened to Layonara.

- **Write the order down (2026-11-14).** We released a version whose new feature needed a plugin the live server
  didn't have switched on. Every test had passed. The page of release steps we follow now was written after it, in
  the order that would have caught it, and step 2 here is its smallest form.
- **Content before the module that needs it.** If the module goes live before its content has been published,
  players are sent to download something that isn't there yet. Publishing first costs nothing, because the running
  game ignores it until the switch.
- **A changed setting needs the container made again.** A restart alone keeps the old settings (chapter 4, step 8).
  It's in our own release notes for the same reason it is in this checklist.
- **Small and often.** Six releases in ten days sounds like a lot. A small release is a short list of changes that
  can be understood, checked and, if needed, undone. A release that holds a month of work can't be undone without
  losing a month of work.

## Tested

On 2026-11-18, on a fresh Hetzner cloud server of the smallest shared type that had been through chapters 1, 4, 5,
6 and 12:

- the plugin check: a module whose plugin is on, one whose plugin is off, one whose plugin has no line at all, a
  script file that is included but missing, and one whose plugin can't be read from it;
- the plugin check reading the switches straight from the server;
- a release of a second version of the example module: backup, old file kept, game stopped and started, healthy
  again, 9 seconds in all, with the new version's line in the log;
- an undo: the first version running again;
- an undo with nothing left to undo, and a release with nothing to release: both refused;
- a release while the backup couldn't be made: refused, and the game not touched;
- a release of a file that isn't a module at all: reported after three minutes as not healthy, then undone, with
  the earlier version healthy again;
- a release that also carried a hak and a talk table: each installed in its own folder;
- making a tag in the module's repository, and pushing one to GitHub (in the full run of tier 1 described in the
  README).

Not tested: a release with players online.

## Tier 2. One routine, a way around every step, and a second pair of hands

### What you learn

By now each part of a release has a tier 2 of its own: the module is tested and staged by a tag (chapter 6), the
tables change through migrations that are rehearsed first (chapter 5), new content is staged and then promoted
(chapter 7), and every night goes off-site, encrypted (chapter 12). This section puts them into one order you can
follow on a tired evening, and then walks through the bad evenings: what to do when each step fails, how to go back,
and what someone else needs to do all of it without you.

When you're done, you'll have:

- the tier 2 release as one checklist, from a merged change to players in the new version;
- [`templates/game/preflight.sh`](../templates/game/preflight.sh), one command on the game host that looks at
  everything the release depends on, changes nothing, and says `ready when you are` or what to look at;
- the staging copy playing your new content too, before your players get it;
- a way around each step when it fails, tested: staging unhealthy, a migration refused, a promote that fails half
  way, a game that won't come back, Coolify down, GitHub down;
- the three ways back, and when each is the right one;
- a one-page runbook for whoever comes after you,
  [`templates/handover/RUNBOOK.md`](../templates/handover/RUNBOOK.md), and the accounts and keys they need.

**Time:** about half an hour to read and set up, and a release itself is mostly waiting for GitHub. On the test,
from pushing the tag to a healthy staging game took under two minutes, and the release itself, with new content,
three migrations and a new module, took 17 seconds from the command to `the game hands out` the new version.

You need the tier 2 sections of chapters 4, 5, 6, 7 and 12 done. The examples use `GAME` for the game host,
`CONTROL` for the control host, and `https://nwsync.example.org` for your download address.

### What Layonara does

- **One written order for every release.** Content first, then the module, then the switch. Ours lives in the
  module's repository, and an agent runs the checks before a person presses the button.
- **Releases are started from a page** that won't let the steps run in the wrong order, and a countdown in the
  game tells players when the restart comes.
- **Four ways to reach the game.** The dashboard, the Discord bot, the operations service directly with `curl`,
  and plain SSH to the game host. Each one is there for the day the one above it is down, and the last one needs
  nothing but a key.
- **Named accounts.** Everyone who helps run the world has their own login everywhere: their own SSH key, their own
  dashboard account. Nothing is shared, so letting someone go is removing one line, not changing every password.
- **A handover page** for the people who share the work, with no secrets in it: it says where they are.
- **Every secret is in a password manager,** in a vault meant for whoever comes after us.

The operations service, the dashboard and the bot are chapters 9 and 10. This section uses only what you have:
the scripts on your two machines, Coolify and GitHub. That turns out to be enough for every fallback here.

### The human playbook

The new file is [`templates/game/preflight.sh`](../templates/game/preflight.sh), for the game host. Two files from
chapter 7 changed with this section, for the staging content and for the fallbacks:
[`templates/content/publish.sh`](../templates/content/publish.sh) and
[`templates/content/promote.sh`](../templates/content/promote.sh), with small changes to `lib.sh`, `prune.sh`,
`content.env.example` and the downloads `Caddyfile` beside them. If you made your copies before this section
existed:

```sh
scp templates/game/preflight.sh nwn@GAME:game/
scp templates/content/*.sh templates/content/Caddyfile templates/content/content.env.example nwn@CONTROL:content/
```

`content.env.example` is only for reading: your own `content.env` stays as it is. The downloads service reads its
`Caddyfile` when it starts, so restart it once in Coolify.

#### 12. ADAPT. Give staging your new content

Change: the address, to your download address.

Chapter 6's staging copy has folders of its own, and until now nothing put haks there, so a module that needs new
content could not start on staging at all. On the test, that was exactly what happened (step 16 shows it). From
this section on, `publish.sh` gives staging the same content it stages for players, so you can try the two
together.

Staging needs one more setting, in its own **Environment variables** in Coolify:

```
NWN_NWSYNCURL=https://nwsync.example.org/staging
```

then its **Restart**. Under `/staging`, the downloads service now has a `latest` of its own, which only the staging
game reads, beside the same files players download. `publish.sh` points it at each new version it stages and
checks it over HTTPS, the way it checks the players' address. So staging hands out the content you're about to
release while your players still get the one they have. The next publish says, near the end:

```
staging has the same content; it hands it out from its next stage
```

If the game host has no `~/staging` folder, `publish.sh` skips this and says nothing.

One thing to know: the staged content can be downloaded by anyone who knows the address, before you release it.
For haks that has never worried me, but if yours hold a surprise, keep that in mind.

#### 13. GENERIC. The release, in order

Keep this part. It is tier 1's checklist with the tier 2 pieces in their places.

**Before**

- [ ] Everything for this release is merged, and the tests and the compile check on `main` are green.
- [ ] The plugin check passes, and the NWNX version is the same everywhere (tier 1, steps 2 and 3).
- [ ] If content changed: `publish.sh` has staged it (chapter 7, step 21).
- [ ] The tag is pushed, and its release ends with `staging is healthy with vX.Y.Z` (chapter 6, step 21).
- [ ] I joined staging and tried what this release is for.
- [ ] Players know when.

**During**

- [ ] Staging's module is in `~/incoming`, with the `migrations` folder if any.
- [ ] `sudo ./preflight.sh` says `ready when you are`.
- [ ] Content changed: `promote.sh` on the control host. Module only: `sudo ./release.sh` on the game host.
- [ ] The last line says the game is healthy (and, after a promote, which version it hands out).

**After**

- [ ] I joined the live game, and tried the thing this release is about.
- [ ] Players know it's done, and what changed.

The first four lines of **Before** can be done hours or days ahead: none of them touches the live game.

Why content comes before the tag: a module that names a new hak can only start where that hak is. The publish
puts it on staging, so the tagged module starts there. The players' `latest` doesn't move until the promote.

#### 14. GENERIC. Put the release in `~/incoming`

The module that goes live is the file staging ran, byte for byte, as in chapter 6's step 22. On the game host:

```sh
cat ~/staging/staged.txt
sudo cp ~/staging/home/modules/mymodule.mod ~/incoming/
```

If content changed, `publish.sh` already put the haks, the talk table and a module in `~/incoming`. The module it
sent was the one you published with; the `cp` replaces it with staging's, which is the one you tried.

If the release brings migrations, send the folder from the tagged commit, from your own computer, as chapter 5's
step 15 shows:

```sh
cd ~/mymodule && git checkout -q v0.2.0
ssh nwn@GAME 'rm -rf incoming/migrations'
scp -r migrations nwn@GAME:incoming/
git checkout -q main
```

#### 15. GENERIC. Look before you leap

On the game host:

```sh
cd ~/game
sudo ./preflight.sh
```

It reads everything the release depends on and changes nothing. On the test, before the release with new content:

```
ok    the live game is healthy
ok    staging is healthy
ok    staging runs v0.2.0, staged 2026-11-26T16:09:45Z
ok    mymodule.mod waits, the same file staging runs (v0.2.0)
ok    my_first_hak.hak waits
ok    my_tlk.tlk waits
ok    migrations: 0 applied, 3 waiting
ok    newest backup here: backups/20261126-160153, 0 h old
ok    newest off-site backup: 0 h old
ok    downloads: https://nwsync.example.org names a5f67333db8d4f7655fcbff94121e8d3e4d497d5, the version the game hands out
ok    staging hands out e719614c926d6c520fc071ef821f726355a64f65
ok    disk 18% full
--    no earlier release to undo yet
nothing to look at: ready when you are
```

Each `LOOK` line says what it saw. The ones that matter most:

- **the module isn't the file staging runs**: copy staging's again (step 14). It means you'd be releasing something
  nobody tried.
- **migrations: PROBLEM**: a migration that already ran has changed. Step 17.
- **the download address doesn't answer**: don't release now. A game that can't fetch `latest` can't start, so a
  restart would leave your world down until the address is back. Step 19.
- **the off-site backups can't be listed**: the nightly copy isn't reaching the storage. The release itself still
  makes its own backup on the game host, but I'd fix this first, on a calm day.

An agent can run this as often as it likes. It is the agent's whole check before a release, and it changes nothing.

#### 16. GENERIC. Go live

Content changed: on the control host,

```sh
~/content/promote.sh
```

which moves `latest` and runs `release.sh` on the game host for you, migrations and all:

```
latest is e719614c926d6c520fc071ef821f726355a64f65 (was a5f67333db8d4f7655fcbff94121e8d3e4d497d5)
0 applied, 3 waiting
...
rehearsal passed: 3 tables in the copy afterwards; the copy is removed
game stopped
applying 0001-server-starts.sql
applying 0002-server-starts-module.sql
applying 0003-release-notes.sql
applied 3, 0 were already applied
installed home/hak/my_first_hak.hak
installed home/modules/mymodule.mod
installed home/tlk/my_tlk.tlk
game started
the game is healthy again
the game hands out e719614c926d6c520fc071ef821f726355a64f65
```

Module only, or migrations only: on the game host, `cd ~/game && sudo ./release.sh`.

Then join, as always. Running `sudo ./preflight.sh` once more afterwards is a nice habit: it should be all `ok`
except that `~/incoming` is now empty.

### When a step fails

Everything up to the moment the game stops can fail without your players noticing. That covers most of what
follows. I tested each of these on purpose, and each one came back.

#### 17. GENERIC. Staging isn't healthy

The tag's release ends red, at its last job, with `the staging game did not become healthy within three minutes`.
Your live game wasn't touched: the workflow can't reach it.

On the game host, look at what staging said:

```sh
docker logs --tail 30 $(docker ps -q --filter label=com.docker.compose.service=staging-nwserver)
sudo grep -a -i -E "couldn't|error" ~/staging/logs/nwengineLog.txt | tail -5
```

On the test I tagged a module that named a second hak I hadn't published yet. The tests on GitHub passed, staging
said only `Unable to load module`, and the engine's log said why:

```
Couldn't load the Hak Pak File "my_second_hak.hak"
```

Since chapter 6's tests download their content from your address (its step 16), the same tag now stops earlier,
at the tests, with `the module needs my_second_hak.hak`, and no release is made: on the test, a tag on a module
naming a hak nobody had published stopped there. A staging that won't start is still worth knowing how to read, for
anything else it lacks.

Two ways forward, depending on what it was:

- **The module is fine, staging lacked something** (content not published, as here): publish it, then run the
  failed job again. In the release's run on GitHub, **Re-run jobs**, **Re-run failed jobs**, or
  `gh run rerun RUN --failed`. On the test that turned it green with `staging is healthy with v0.3.0`.
- **The module is wrong**: fix it in a pull request, merge, and tag the next version, as chapter 6's step 22 says.
  Live never saw the broken one.

#### 18. GENERIC. A migration is refused

`release.sh` stops before it makes its backup, or right after it, and says `release stopped before anything
changed`. Your game kept running. There are two kinds:

- `PROBLEM: 0002-....sql has changed since it ran`: the file in `~/incoming/migrations` isn't the one that ran on
  the live database. Usually the folder came from the wrong commit, or someone tidied an old file. Send the folder
  again from the tagged commit (step 14). If the change was on purpose, put the old file back and make the change
  in a new, higher-numbered file (chapter 5, step 13). `preflight.sh` shows this one before you start.
- `REHEARSAL FAILED`: a waiting migration failed on the copy of last night's data. It never ran on the live
  database, so fix the file and release again.

#### 19. GENERIC. A promote fails half way

`promote.sh` moves `latest` first and then runs the release. If the release stops before it changed any file, for
any of the reasons in step 18 or a backup that couldn't be made, `promote.sh` now puts `latest` back by itself:

```
release stopped before anything changed: the migrations failed on a copy
the release stopped before it changed any file; latest is a5f67333db8d4f7655fcbff94121e8d3e4d497d5 again, and e719614c926d6c520fc071ef821f726355a64f65 is still staged
```

Fix the cause and run `promote.sh` again; the content is still staged. (Before this section it left `latest` on the
new version, and the next restart of the game would have handed out content its haks didn't match. I found that
while testing this step.)

If the release did change the files, and the game didn't come back, it says so and names the way back:

```
the release changed files and the game is not healthy. To go back to a5f67333db8d4f7655fcbff94121e8d3e4d497d5 and the old files: /home/nwn/content/promote.sh --back
```

Run that. On the test, with a module file that was really noise, it took 7 seconds to have the earlier version
running again.

#### 20. GENERIC. The game won't come back

First, the way back for the release: `sudo ./release.sh --undo` (or `promote.sh --back` after a promote). If even
the old version won't start, the cause isn't the release. Look at what the game says:

```sh
docker logs --tail 30 $(docker ps -q --filter label=com.docker.compose.service=nwserver) 2>&1 | grep -a -v '^\s*$'
```

and `sudo ./preflight.sh`, which sees most of the usual causes. Three to look for:

- **A missing hak**: `Unable to load module`, and the engine's log names the file (step 17's commands, with
  `~/game/logs`).
- **The database**: the game's database container isn't healthy. `docker ps` shows it, and `docker logs` on it
  says why. A full disk is one reason, and `preflight.sh` shows how full it is.
- **The download address**: the game asks `latest` every time it starts, and doesn't start without an answer. On
  the test, with the downloads service stopped, Docker restarted the game four times in 45 seconds, and its log
  said:

  ```
  NWSync: Failure to get latest manifest hash: HTTP response code said error: 503 (The requested URL returned error: 503 Service Unavailable)
  ```

  Get the address answering and the game comes back by itself. If the control host is gone for longer, you can
  tell the game which version to hand out, so it doesn't ask: add `NWN_NWSYNCHASH=` with the version your game
  last handed out (the 40 characters from `now advertising` in an earlier log, or from `cat ~/nwsync/latest` on
  the control host) to the game's settings, and restart it. On the test it started healthy within a minute with the
  address still down. Players who already have that content can play; anyone who needs to download waits for the
  address. **Take the setting out again** once the address is back, and restart: while it's there, your game keeps
  handing out that version, whatever you promote.

#### 21. GENERIC. Coolify is down

This is the good news of the chapter. Nothing in a release goes through Coolify. `stage.sh`, `release.sh`,
`publish.sh`, `promote.sh`, `preflight.sh` and the backups all talk to Docker on the machines themselves. Coolify
started the containers, and Docker keeps them running.

On the test I stopped Coolify on the control host (its own containers, `coolify`, `coolify-db` and
`coolify-redis`), and then:

- the downloads kept answering: they are served by Coolify's proxy and their own container, which carry on;
- a full release with new content went through in 10 seconds, the same as any other;
- the game host rebooted, and the game, its database and staging all came back healthy by themselves, with
  Coolify still stopped.

What you can't do while it's down is change a setting, because that means making the containers again. If it can't
wait, you have tier 1 on the game host: the compose files and your written copy of the settings in `~/game/.env`
(chapter 4, step 13). On the game host:

```sh
cd ~/game
nano .env                     # the change, for example a plugin switched on
docker rm -f $(docker ps -aq --filter label=coolify.managed=true --filter label=com.docker.compose.service=nwserver) \
             $(docker ps -aq --filter label=coolify.managed=true --filter label=com.docker.compose.service=mariadb)
docker compose up -d
```

`docker rm -f` stops Coolify's game and database and removes them. Removing them matters: `backup.sh`,
`release.sh` and `preflight.sh` find the game by its service name, and with a stopped Coolify one still there
beside the new one they find two and refuse, rightly unsure which you meant. I found that out by stopping them only.
Coolify makes them again at its next deploy. The data is the same folders in both cases, so nothing moves. On the
test the game was away for 13 to 14 seconds, came back with the new setting, and a release afterwards worked as usual.

When Coolify is back, it shows the game as stopped and leaves it alone. Put the same change into its
**Environment variables**, then, close together:

```sh
cd ~/game && docker compose stop nwserver mariadb && docker compose rm -f nwserver mariadb
```

and the service's **Deploy**. That's chapter 4's switch again; on the test it took 17 to 18 seconds.

#### 22. GENERIC. GitHub is down

Without GitHub there is no tag release, and `publish.sh` can't pull your content. Neither stops a release.

For the module, build it at home the way your compile check does, and stage it by hand with your own login:

```sh
cd ~/mymodule && git checkout -q main
nasher pack default --yes --abortOnCompileError && python3 tools/check_compiled.py mymodule.mod src
ssh nwn@GAME 'sudo staging/stage.sh "stage v0.3.1"' < mymodule.mod
```

For content, bring the commit across yourself, and tell `publish.sh` not to pull:

```sh
cd ~/myhaks && git push nwn@CONTROL:myhaks HEAD:refs/heads/from-home
ssh nwn@CONTROL 'git -C ~/myhaks merge --ff-only from-home && PULL=no ~/content/publish.sh ~/mymodule.mod'
```

`git push` can't change the branch the control host has checked out, so it goes to a branch of its own, and the
merge moves `main` to it. Send the module you built to the control host first, as for any publish. Then release as
usual. On the test, with the content's repository out of reach, `publish.sh` stopped at its `git pull` as it
should, and this way staged the content, staged the module, and released both.

When GitHub is back, push your commits from your own computer and push the tag, so git and GitHub's releases say
what's live. The tag's workflow builds and stages the module again, which only touches staging. Leave live as it is.

#### 23. GENERIC. The three ways back

| What went wrong | The way back | What it changes |
|---|---|---|
| The new module or haks misbehave | `sudo ./release.sh --undo` on the game host | the files the last release replaced, and nothing else |
| A promote went wrong | `~/content/promote.sh --back` on the control host | `latest` back, and then the same undo |
| What's stored in the database is wrong | `sudo ./restore-db.sh backups/...` on the game host | the whole database, back to that backup |

Go back first, understand later, as in tier 1. And the order of the three matters: files first, because that's
cheap and loses nothing. The database last, because everything your players did since that backup goes with it.
On the test, after the full release: `promote.sh --back` had the old content and module running in 9 seconds and
named the three migrations it couldn't undo, and `restore-db.sh` of the backup made just before the release took 3
seconds, after which `./migrate.sh status` listed all three as waiting again.

If a migration only added a table or a column, the old module usually runs fine beside it, and the files are all
you need to put back.

### Handing over

Sooner or later someone else will release while you're away, or after you've gone. Tier 2 is the first point where
that's possible without you on the phone, so here is what they need.

#### 24. GENERIC. Their own accounts

Give each person their own login, everywhere, and never share yours. Then letting someone go is one line, and a log
says who did what.

- **SSH**: their key on the deploy user of both machines, with a comment that names them:

  ```sh
  ssh nwn@GAME 'cat >> ~/.ssh/authorized_keys' < sam.pub
  ssh nwn@CONTROL 'cat >> ~/.ssh/authorized_keys' < sam.pub
  ```

  and to take it away again, `sed -i '/sam@laptop/d' ~/.ssh/authorized_keys` on each. On the test a second key ran
  `preflight.sh` and the tidy-up, and after the `sed` it was refused.
- **Coolify**: invite them into your team in the dashboard, so they log in with a password of their own.
- **GitHub**: on the module and content repositories, a role that may push tags (**Maintain** or **Write**). If you
  limited who may release (the `staging` environment's **Required reviewers**), add them there.
- **The provider's console**: a member of your project, so they can reach the machines' firewall and rescue mode
  when SSH can't.
- **DNS and the domain**: a member at your DNS provider, and at least one other person who can renew the domain.

#### 25. GENERIC. The vault

Keep every secret the world needs in a password manager, in a vault you share with the people who'd carry on
without you. Chapter 12 already put the borg passphrases and keys there, and Coolify's `APP_KEY`. Add a copy of the
game's settings (`~/game/.env`), so a new machine can start without Coolify, and the recovery codes for each
account. Then tell someone the vault exists. A vault nobody knows about is the same as no vault.

#### 26. ADAPT. The runbook

Change: everything in capitals.

[`templates/handover/RUNBOOK.md`](../templates/handover/RUNBOOK.md) is one page: who, which machines, which
accounts, where each secret lives (never the secret itself), the release in seven lines, and a table for a bad day.
Copy it into your module's repository, fill it in, and keep it next to the code, so a change to the setup and a
change to the page come in the same pull request.

The line I'd protect most is **Last checked**. A runbook nobody has followed is a guess. Once in a while, ask the
second person to do a release with only that page and nothing else, while you watch and say nothing. Whatever they
had to ask you belongs on the page.

#### 27. LAYONARA-ONLY. Four ways in

Our game can be reached four ways: a dashboard, the Discord bot, the operations service by `curl`, and plain SSH.
The first three are chapters 9 and 10. The last one is this section, and it is the one that works when everything
else is down.

### The agent playbook

If you work with an AI agent, [`playbooks/16-releasing-tier2.md`](../playbooks/16-releasing-tier2.md) prepares a
tier 2 release and checks it: everything up to `preflight.sh`. Going live, every fallback that restarts something,
and every way back are your yes, every time.

### Lessons

- **Move the pointer back when nothing moved.** `promote.sh` moves `latest` before the release, so the game reads
  the new version as it restarts. On the test, a release that was refused at its rehearsal left `latest` naming
  content the game host didn't have yet, and nothing said so: the game kept running, and the next restart would
  have handed players content that didn't match its haks. `promote.sh` now checks whether the release changed any
  file, and puts `latest` back when it didn't.
- **Staging needs the content too.** The first time I tagged a module that used a new hak, the tests on GitHub
  passed (my test repository gave them the hak) and staging couldn't start (nothing had given it the hak). That was staging doing its job, and it is also
  why the content now goes to staging when it is staged, and why the routine publishes before it tags.
- **Stopped isn't gone.** In the Coolify-down test I stopped Coolify's game containers and started tier 1's in their
  place. The game was fine; the scripts weren't, because they found two of each by name. Removing the stopped ones
  fixed it, and Coolify makes them again.
- **Keep the controller out of the release.** Nothing in this routine runs inside Coolify or waits on it. That's
  why it kept working with Coolify stopped, and why a reboot of the game host while Coolify was down cost nothing.
- **Write it down where the code is.** Our own release order is a page in the module's repository, written after a
  release that went less smoothly than it should have (tier 1's lessons). The runbook belongs beside it for the same
  reason: a page somewhere else drifts away from what the machines really do.

### Tested

On 2026-11-26, on two fresh Hetzner cloud servers of the smallest shared type (Ubuntu 26.04, Docker 29.1) brought to
the tier 2 state of chapters 1, 3, 4, 5, 6, 7 and 12, with Coolify 4.7.5, `nwnxee/unified:ed79330`, MariaDB 11.8,
borg 1.4.4, Caddy 2.11, the builder image with neverwinter.nim 2.3.2, and a private throwaway module repository on
GitHub with chapter 6's workflows:

- one full release in this section's order: content published (and given to staging), a tag `v0.2.0` staged by
  GitHub in under two minutes with that content, `preflight.sh` all `ok`, and `promote.sh` releasing the content,
  three migrations and the module in 17 seconds; the status tool answering on both ports afterwards;
- going back after it: `promote.sh --back` (9 seconds) and `restore-db.sh` of the backup made just before (3
  seconds), the ledger listing the three migrations as waiting again; a later release of migrations only;
- staging unhealthy: a tag whose module needed an unpublished hak, live untouched, the cause read from staging's
  engine log, the content published and the failed job re-run to `staging is healthy with v0.3.0`;
- a migration refused for a changed file (no backup made, the game untouched, `preflight.sh` reporting it first),
  and one that failed its rehearsal inside a promote, with `latest` put back by itself and the content still staged;
- a promote that swapped in a module file that was noise: not healthy after three minutes, and `promote.sh --back`
  healthy again in 7 seconds;
- the game unable to start while the downloads service was stopped (four restarts in 45 seconds), started healthy
  with `NWN_NWSYNCHASH`, and handing out the latest version again once the setting was removed;
- Coolify stopped: the downloads still served, a full release with new content (10 seconds), a reboot of the game
  host with everything back by itself, a setting changed through tier 1's Compose (game away 14 seconds), a release
  under Compose, and the move back into Coolify (17 seconds);
- GitHub out of reach (the content repository moved aside, the module built at home with nasher 1.2.2): `publish.sh`
  refusing at its pull, then `PULL=no` with the commit pushed across, a hand stage, and a promote;
- a second person's key on both machines, used for a check and taken away again;
- the off-site backup: `preflight.sh` reading the newest borg archive's age, with the control host standing in for the
  storage provider.
- this chapter's agent playbook, as written, for a release `v0.4.0` with content and a migration: it stopped at
  step 5 on a `LOOK` that an earlier test had left (a migration changed after it ran), as it should, and after that
  was put right it went through to `the game hands out` the new version;
- the `/staging` address answering with `Cache-Control: no-store` on its `latest`, like the players' one, and the
  tidy-up running after each promote with the `/staging` folder in place.

The content repository was a plain git repository on the control host standing in for GitHub, as in chapter 7's
test; the Coolify settings were changed through its API, which does what the dashboard pages do. The module used two
haks, so the test server in GitHub's tests needed them: in the test repository they were committed beside the tests
and given to `tests/run.sh` as `TEST_HAK_DIR` and `TEST_TLK_DIR` (chapter 6, step 16).

Not tested: a release with players online, a player joining while the version was pinned with `NWN_NWSYNCHASH`, a
second person's Coolify or GitHub account (only the SSH key), and a game client on staging (the status query
answered instead).
