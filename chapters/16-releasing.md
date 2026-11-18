# Chapter 16. Day to day: releasing

**Status:** tier 1 is written and tested. Tier 2 (fallbacks, handing the server over to someone else) and tier 3 (a
calendar of things that expire, and our full list of incidents) are not written yet.

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
