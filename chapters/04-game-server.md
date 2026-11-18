# Chapter 4. The game server and NWNX

**Status:** tier 1 is written and tested. Tier 2 (building your own image) and tier 3 (your own plugins, release
tags) are not written yet. Chapter 3 is about Coolify, which tier 1 doesn't use, so it is fine to arrive here
straight from chapter 2.

## What you learn

How to run the Neverwinter Nights server, with NWNX, in one container on the machine from chapter 1. This is the
chapter where something you can connect to appears.

When you're done, you'll have:

- a game server that answers on your machine's address or name, running the small demo module that comes in the
  image;
- a server that starts by itself after a crash, after a Docker update and after a reboot;
- one settings file that holds everything you chose, and one line in it that decides which version runs;
- NWNX in place, with a plugin switched on, and the habit of switching on only what your scripts use.

Your own module comes in chapter 6 and the database in chapter 5. Starting with the demo module is on purpose: if
something doesn't work today, you know it isn't your module.

**Time:** about ten minutes. Most of it is the first download of the image, which is about 260 MB. On the test
machine the server answered 7 seconds after it started.

## What Layonara does

- **One image, from our own fork of NWNX.** It is built automatically every time a change is merged, in about nine
  minutes. The fork adds four plugins of our own, and our module can't run without them. Yours almost certainly
  can, which is why this guide starts you on the community's image and leaves forking for tier 3.
- **Three containers side by side:** the game server, a MariaDB database and Redis, in one Compose file. This
  chapter builds the first of them.
- **Plugins are off until asked for.** The image starts with every NWNX plugin switched off, and we switch on about
  thirty, one line each.
- **Room for 64 players**, a server that restarts by itself, and a health check.
- **The version changes only on purpose.** Our game host never fetches a newer image on its own. It changes when
  one of us decides to, as a step of a release.
- **Two logs.** The game writes its own log files to a folder on the host. Everything NWNX says goes to Docker's
  log, which chapter 1 capped at three files of 10 MB.

## The human playbook

Each step carries a label: GENERIC (the same for any server), ADAPT (works once you change the things it names) or
LAYONARA-ONLY (something we do that you probably shouldn't copy).

The files for this chapter are in [`templates/game`](../templates/game): a Compose file, an example settings file
and a small tool that asks a server whether it is up. They're short, and worth a read before you use them.

`SERVER` below is your machine's address, or its name if you did chapter 2.

### 1. GENERIC. Choose the version

The community publishes a ready-made image, `nwnxee/unified`, with the game server and NWNX inside. Its tags come
in two kinds:

- **A build tag**, such as `build8193.37.17`, follows the newest NWNX for that build of the game. It moves whenever
  NWNX changes.
- **A commit tag**, seven letters and digits such as `ed79330`, names one exact version and never moves.

Put a commit tag in your settings. Then your server changes version only when you change that line, and going back
is putting the old tag in again. To find the commit tag behind today's build tag:

```sh
ssh nwn@SERVER 'docker pull -q nwnxee/unified:build8193.37.17 >/dev/null && docker image inspect nwnxee/unified:build8193.37.17 -f "{{index .Config.Labels \"org.opencontainers.image.revision\"}}" | cut -c1-7'
```

On the day of the test this printed `ed79330`. The build number should be the one your players' game is on, so use
the build tag for the current game where I used `8193.37.17`.

### 2. GENERIC. Copy the files to the server

From this repository, on your own computer:

```sh
scp -r templates/game nwn@SERVER:game
```

Everything about the game now lives in one folder, `~/game`, on the server.

### 3. ADAPT. Fill in your settings

Change: the server's name, the passwords, the player limit, and the tag from step 1.

```sh
ssh nwn@SERVER
cd game
cp .env.example .env && chmod 600 .env
nano .env
```

The file explains itself. Three things are worth a word here:

- **The two passwords you must set** are for dungeon masters and for the server's administrator. The server won't
  start while either is empty, and that is deliberate. `openssl rand -hex 8` makes a good one. The player password
  can stay empty if anyone may join.
- **`NWN_MODULE=DockerDemo`** is the small module inside the image. Leave it for now.
- **`NWN_PUBLICSERVER=0`** keeps you out of the game's public server list while you set up. Step 9 turns it on.

The passwords end up on the server's command line, so anyone who can log in to the machine can read them. That is
one more reason the machine is yours alone.

### 4. GENERIC. Start it

Still in `~/game` on the server:

```sh
docker compose up -d
docker compose ps
```

The first start downloads the image, about 260 MB, and that is most of the wait. After a few seconds `docker
compose ps` should show `Up` and `(healthy)`. Healthy means something specific here: every 30 seconds the container
asks its own server the question a player's game asks, and counts it healthy when the server answers.

If it doesn't get there, `docker compose logs --tail 50` shows what the server said. A missing password is the
usual cause on a first try, and the message says which one.

### 5. GENERIC. Check it from outside

From your own computer, in this repository:

```sh
templates/game/nwn-status.py SERVER
```

You should see something like `SERVER port 5121 is up: module DockerDemo, room for 16 players`. This asks from
outside, across the internet and through both firewalls, so it proves the whole road a player travels.

Then the nicest check of all: open the game, choose Multiplayer, then Join Internet Game, then Direct Connect, and
type `SERVER:5121`. Once you've made a character, you should arrive in the small demo module.

### 6. GENERIC. Have a look around

Two folders appeared in `~/game` on the first start:

- `home/` holds everything the server keeps: `modules`, `hak`, `tlk`, `servervault` (your players' characters),
  `database` and a few more. Later chapters put things in them. It also holds `settings.tml`, the game's own
  settings file, and `cryptographic_secret`, the server's own key. Keep both; they are part of what you back up.
- `logs/` holds the game's log files. `nwserverLog1.txt` is the one you'll read most.

The files in both belong to root, because the server runs as root inside its container. So it's `sudo ls` and `sudo
cp` when you work in there.

What NWNX and the server print goes to Docker's log instead:

```sh
docker compose logs --tail 50
```

### 7. GENERIC. Talk to the server's console

```sh
docker attach game-nwserver-1
```

Now you are typing at the server itself. `status` shows the settings and who is online, `help` lists the rest, and
`say hello` speaks to everyone in the game.

**Leave with Ctrl-P and then Ctrl-Q.** Please don't leave with Ctrl-C: I tried it so you don't have to, and it
shuts the server down. If it happens anyway, nothing is lost. The server starts again by itself a few seconds
later.

### 8. GENERIC. Switch a plugin on

NWNX is a set of plugins, and in this image every one of them is off until you ask for it. That's a good default: a
plugin you don't use can't surprise you. You ask with one line in `.env` per plugin:

```
NWNX_ADMINISTRATION_SKIP=n
```

Then apply it:

```sh
docker compose up -d
docker compose logs | grep "Loaded plugin"
```

You should see a `Loaded plugin` line for it, beside the ones for `Core`, `ServerLogRedirector` and `Util`.

Two things I'd like you to keep from this step:

- **A changed setting only arrives with `docker compose up -d`.** `docker compose restart` starts the same
  container again with its old settings. I tested both: after `restart` the new plugin wasn't there, after `up -d`
  it was. This catches everyone once.
- **Which plugins do you need?** Exactly the ones your module's scripts use. Each plugin comes with a script file
  named `nwnx_<something>.nss`, and a script that includes that file needs that plugin switched on. Chapter 6 comes
  back to this when your own module arrives.

### 9. ADAPT. Decide whether to be listed

Change: whether strangers should find you.

Set `NWN_PUBLICSERVER=1` in `.env`, run `docker compose up -d`, and your server appears in the game's public list.
The log says so:

```
{Masterserver Advisory} Server is visible on public listing with address ...
```

On the test it was in the list within about half a minute, and gone from it again soon after I set it back to 0. If
you'd like to stay private while you build, leave it at 0. Players can still join with Direct Connect.

### 10. GENERIC. The everyday commands

All from `~/game` on the server:

| You want to | Command |
|---|---|
| See whether it's up | `docker compose ps` |
| Read what it said | `docker compose logs --tail 100` |
| Stop it | `docker compose stop` |
| Start it again | `docker compose start` |
| Apply a changed `.env` | `docker compose up -d` |

A stop is polite: the server gets the message, says `Server shutting down` and is gone in under two seconds. You
don't have to do anything for a crash, a Docker update or a reboot. In all three the server came back, or simply
kept running, without help on the test.

### 11. GENERIC. Changing the version, and going back

When a new NWNX version is out and you'd like it:

1. Note the tag you run now. It's the `NWNX_IMAGE` line in `.env`.
2. Find the new commit tag as in step 1 and put it in `.env`.
3. `docker compose pull && docker compose up -d`
4. Check as in steps 4 and 5.

If you don't like what you see, put the old tag back and run `docker compose up -d` again. The old image is still
on the machine, so going back takes seconds. I moved the test server to an older version and back this way.

A new build of the game itself is a bigger event, because your players' games update too and everyone has to move
together. This guide's later tiers cover it.

### 12. LAYONARA-ONLY. Our own fork of NWNX

We build our image from a fork because our module needs plugins that only exist there. A fork is a commitment:
every upstream change has to be merged in, and the image has to be built and published. Please don't start with
one. If the day comes when you need something NWNX doesn't do, tier 3 shows how we keep ours.

## The agent playbook

If you work with an AI agent, [`playbooks/04-game-server.md`](../playbooks/04-game-server.md) has these same steps
in a fixed shape it can follow. The passwords never pass through the agent: you put them in `.env` yourself, or let
the playbook's one command make them on the server without showing them.

## Lessons

These are the things that went wrong for us, written down so they don't have to go wrong for you. The dates are
when they happened to Layonara.

- **Know which version is running, and change it on purpose (2026-11-14).** We released a version of our module
  that used a new plugin, while the game host's image didn't have that plugin yet and its switch wasn't set. The
  feature failed for every player who tried it. Our tests had passed, because they ran against a newer image than
  the one the players were on. Since then a check before each release compares what the module's scripts include
  with what the live image has and has switched on. The commit tag in step 1 is the same idea in its smallest form.
- **A setting isn't live until the container is made again.** This is step 8. The same note sits in our own release
  checklist, because a changed line followed by a plain restart looks exactly like a setting that doesn't work.
- **Let the health check ask the server, not read a file (2026-10-26).** One of our health checks decided by
  looking at how fresh a log file was. On a quiet day the file sat still and a perfectly good server was reported
  as unhealthy. The check in this chapter's template asks the server a question and waits for the answer.
- **Docker doesn't restart a container for being unhealthy.** It restarts one that stops. The health check is there
  so that you, and later your monitoring, can see the state at a glance.

## Tested

On 2026-11-18, on a fresh Hetzner cloud server of the smallest shared type that had just been through chapter 1,
with the image `nwnxee/unified:ed79330` (game build 8193.37.17):

- that the server refuses to start while a required password is empty, and says which one;
- a first start to healthy in 7 seconds (after the download), and the status tool answering from another computer;
- the status tool itself: a running server, a closed port, a name that doesn't exist, and an address that isn't a
  game server;
- a stop (1.5 seconds, clean exit) and a start;
- a crash, by killing the server process: back and healthy within 12 seconds;
- a restart of the Docker service: the same server process kept running and kept answering;
- a reboot of the machine: the server came back by itself and answered;
- the console: `status` and `help`, leaving with Ctrl-P Ctrl-Q, and what Ctrl-C does;
- switching a plugin on, with both `restart` (not applied) and `up -d` (applied);
- a frozen server process: reported unhealthy after 81 seconds, not restarted by Docker, healthy again once it was
  let go;
- moving to an older version and back;
- the public list: listed within about half a minute of switching it on, and gone again after switching it off.

With nobody online and the demo module, the server used about 15% of one shared core and 81 MB of memory.

Not tested: logging in with the game itself (I checked with the status question and the public list, not with a
player), a module other than the demo, a server with players on it, and a game build other than 8193.37.17.
