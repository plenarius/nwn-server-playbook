# Chapter 4. The game server and NWNX

**Status:** tiers 1, 2 and 3 are written and tested. Tier 1 runs the game with plain Docker Compose; tier 2, further
down, hands it over to Coolify; tier 3, at the end, builds your own NWNX image with your own plugin.

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
one. If the day comes when you need something NWNX doesn't do, tier 3, at the end of this chapter, shows how we keep
ours.

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
- joining with the game itself by Direct Connect to the address, once as a dungeon master with the DM password from
  `.env` and once as a player with a new character: the server logged both visits;
- that the player's character was saved under `home/servervault`, and was still there, unchanged, after the
  container was removed and made again.

With nobody online and the demo module, the server used about 15% of one shared core and 81 MB of memory.

Not tested: a module other than the demo, a server with more than one player on it, and a game build other than
8193.37.17.

---

## Tier 2. The game in Coolify

### What you learn

How to hand your running game over to Coolify from chapter 3, without moving a single file of its data. Afterwards
you start, stop, update and watch it from the dashboard, its settings live in one place, and the backup and release
scripts from chapters 12 and 16 carry on working as before.

When you're done, you'll have:

- the game and its database as one Coolify service on the game host;
- their data exactly where tier 1 put it, in `~/game`;
- the database administrator's password kept out of Coolify altogether;
- the way back to plain Docker Compose, tested, should you ever want it.

Your players lose the game for about 20 seconds during the switch: 19 on the test.

### What Layonara does

- **The game is a Docker Compose service in Coolify**, with three containers: the game server, MariaDB and Redis.
- **Its data folders stayed where our older, hand-run setup kept them.** The Coolify service simply points at them,
  which is the approach this section takes too.
- **Its settings are about 150 lines** in Coolify: the module, the passwords and one switch per NWNX plugin.
- **The image is chosen by one setting**, and a new NWNX version reaches the live game only when one of us changes
  it and redeploys.

### The human playbook

You need chapter 3 done, with the game host added to Coolify. The examples use `GAME` for the game host's address.

#### 13. GENERIC. Know what changes, and what doesn't

**Coolify starts and stops the game** from now on. The containers get new names, such as `nwserver-` followed by
the service's id, instead of `game-nwserver-1`.

**The data doesn't move.** `~/game/home`, `~/game/db` and `~/game/logs` stay where they are, and the new service
uses them in place.

**The settings move into Coolify.** Your `~/game/.env` stays behind as your written copy of them. Chapter 3's
lesson applies: when you change a setting in Coolify, change it there too. The nightly backup takes that file.

**One setting doesn't move at all: the database administrator's password.** Coolify gives every setting of a
service to every one of its containers. I checked: a setting added for the database also showed up inside the game
server. The database already exists from tier 1 and doesn't need that password to start, so it stays in
`~/game/db.env`, out of Coolify and out of every container.

#### 14. GENERIC. Update the backup and release scripts first

The versions of `backup.sh` and `release.sh` in this repository find the game's containers by name, so they work
whichever of plain Compose or Coolify started them. Older copies used `docker compose` in `~/game` and stop working
after the switch. Copy the new ones before you start:

```sh
scp templates/game/backup.sh templates/game/release.sh nwn@GAME:game/
ssh nwn@GAME 'cd game && sudo ./backup.sh'
```

That last command also gives you a fresh backup to stand on for the switch.

#### 15. ADAPT. Create the service

Change: the three paths in the file, if your deploy user isn't `nwn`.

In the dashboard: **Projects**, make one called `game`, and add a resource: **Docker Compose**. Choose the game
host as its server, and paste in [`templates/game/coolify.yaml`](../templates/game/coolify.yaml). **Don't deploy
yet**: it has no settings.

The file is chapter 4 and 5's two Compose files in one, with two differences. Its folders are full paths into
`/home/nwn/game`, so Coolify uses tier 1's data. And it has no administrator password for the database.

#### 16. GENERIC. Copy your settings across

On the game host, print your settings, leaving out the one line that only plain Compose needs:

```sh
ssh nwn@GAME "grep -v -E '^(#|$|COMPOSE_FILE=)' game/.env"
```

That shows your passwords on your own screen, so mind who's looking. In the service's **Environment variables**,
switch to **Developer View**, paste the lines, and save. **Don't paste `db.env`.**

#### 17. GENERIC. Switch over

Two commands, close together, at a quiet time:

```sh
ssh nwn@GAME 'cd game && docker compose stop nwserver mariadb && docker compose rm -f nwserver mariadb'
```

and then in Coolify, the service's **Deploy** button. The first command names the game and its database only, so if
the game host also serves your downloads or website (chapters 7 and 11), they keep running; they move to the
control host in those chapters' tier 2. Both containers should end up **Running (healthy)** on the service's page.
Then check it as in chapter 4's step 5:

```sh
templates/game/nwn-status.py GAME
```

and see that the database still holds what it held, as in chapter 5's step 6. On the test, every row and the
character files were still there, unchanged.

#### 18. GENERIC. The everyday commands, in tier 2

| You want to | Now |
|---|---|
| See whether it's up | The service's page in Coolify |
| Restart it | The service's **Restart** in Coolify |
| Change a setting, or switch a plugin on | Change it in **Environment variables**, then **Restart**. Then change `~/game/.env` to match |
| Move to another NWNX version | Change `NWNX_IMAGE` in **Environment variables**, then **Restart** |
| Read what it said | The service's logs in Coolify, or `docker logs` with the container's name |
| Talk to the console | `docker attach` with the container's name, as before; leave with Ctrl-P Ctrl-Q |
| Release a new module | `sudo ./release.sh`, exactly as in chapter 16 |
| Find the containers' names | `docker ps --format '{{.Names}}'` on the game host |
| Follow another chapter's `docker compose exec mariadb ...` or `docker compose logs ...` | The same with `docker exec -i` or `docker logs` and the container's name, such as `mariadb-` and the service's id |

On Coolify 4.7.5, both **Restart** and **Deploy** made the containers again with the new settings; I tested a
plugin switch and a change of NWNX version with each. A `docker restart`, or a restart from inside the game, keeps
the old settings, as in tier 1.

#### 19. ADAPT. Coolify's proxy on the game host

Change: only if the game host still serves downloads or a website.

Coolify started its web proxy on the game host when you added it. In tier 2 the downloads and the website move to
the control host (chapters 7 and 11), so the game host has nothing for it to do. Stop it on the game host's
**Proxy** page (**More actions**, **Stop Proxy**), as chapter 3's step 6 describes, and keep ports 80 and 443
closed at the game host's provider firewall.

#### 20. GENERIC. The way back

If you ever want plain Compose again: the service's **Stop** in Coolify, then

```sh
ssh nwn@GAME 'cd game && docker compose up -d'
```

Wait until Coolify shows both containers stopped before you run it: two databases must never use the same folder at
once. Tier 1's files are still in `~/game`, and the data never moved. I went back and forth once on the test, with
a backup and a release in between, and nothing was lost either way. Copy any settings you changed in Coolify into
`~/game/.env` first.

#### 21. LAYONARA-ONLY. Redis and 150 settings

Our service has a third container, Redis, which carries commands from our Discord bot into the game, and about 150
settings. Both are tier 3 subjects. The pattern is the same: one service, data folders on the host, settings in
Coolify, with a written copy.

### The agent playbook

If you work with an AI agent, [`playbooks/04-game-server-tier2.md`](../playbooks/04-game-server-tier2.md) has these
steps in a fixed shape it can follow. It copies the settings without ever showing them, and the switch, which
disconnects players, is always your yes.

### Lessons

- **Coolify shares every setting with every container.** I first wrote the template the other way round, expecting
  a setting named under one container to stay with it. The test showed the database's administrator password inside
  the game server, so the template now leaves that password out of Coolify entirely.
- **Leave the data where it is.** Pointing the new service at the folders the old setup used meant the switch moved
  nothing, and the way back is just as short. We moved our own game into Coolify the same way.
- **Make the scripts find containers by name.** Container names change between plain Compose and Coolify, and
  between deploys in Coolify. Scripts that ask Docker for "the container called `nwserver` in a Compose file" keep
  working through all of it.

### Tested

On 2026-11-18, with Coolify 4.7.5, on a game host in the state tier 1 leaves it (game, database, the example module
and a nightly backup) and a control host from chapter 3:

- the switch: tier 1 stopped and the Coolify service started on the same folders, the game away for 19 seconds;
  every database row and a character file unchanged by checksum;
- where settings go: a probe service showed Coolify gives every setting with a value to every container; the
  administrator password then removed from Coolify, absent from both containers, and still working from `db.env`;
- the new `backup.sh` and `release.sh` against the Coolify service: a backup by hand and by the nightly timer, a
  backup refused while the database was stopped, a release in 9 seconds and an undo;
- a plugin switch and a change of NWNX version, each applied by **Restart** and by **Deploy**;
- a reboot of the game host: both containers back, healthy, with their data; the console through the new name;
- the way back: the service stopped, tier 1's Compose started on the same data, a backup and a release with the new
  scripts there, then the Coolify service started again.

- the agent playbook as written on a second, fresh pair, its roll back included; and, by a slip in my own test run,
  tier 1's database started while the Coolify one was running: MariaDB refused to open the files the running copy
  held, and the running database was unharmed. The roll back now checks first.

- the switch on a game host that also served downloads and a website with tier 1's web server: stopping only the
  game and its database left both running throughout, and the game was away for 21 seconds.

The service was made, and its settings copied, through Coolify's API, which does what those dashboard pages do; the
labels quoted here were read from the dashboard on the day.

Not tested: pasting into **Developer View** by hand, Redis in the service, and a game with players during the
switch.

---

## Tier 3. Your own NWNX image

### What you learn

How to build NWNX yourself, with a plugin of your own in it, and run your game on the result. NWNX is open source,
and adding a plugin is an ordinary thing to do: it's how most of NWNX's own plugins started. All you need is a copy
of its source on GitHub, a workflow that builds it, and a place to keep the images.

When you're done, you'll have:

- your copy of NWNX on GitHub, with an example plugin that answers from NWScript;
- an image built by GitHub Actions on every merge, kept on GitHub's container registry (GHCR);
- two tags for each build: one named after the commit, which is pushed once and never replaced, and one that moves
  with each new build;
- your game pinned to a commit tag, and a clear idea of when the moving tag is the better choice.

**Time:** about an hour, of which the first build is ten minutes. Later builds take three.

### What Layonara does

- **Our own copy of NWNX**, public on GitHub, with four plugins of our own beside upstream's: one for our game
  rules, one that lists the looks an item can take, one for chess against an engine, and one that plays a fake
  player for our tests. Our module can't run without them.
- **Game rules in one plugin, everything else upstream.** The plugin with our game rules stays ours. Anything another
  server could use goes to upstream NWNX as a pull request, and many of our fixes are upstream now. The fewer
  differences we carry, the easier each upstream merge is.
- **A build on every merge**, in about nine minutes on GitHub's own machines: compile, then an image on GHCR.
- **A tag per commit, and a moving one.** Every build is tagged with its commit, and those tags are our whole
  history of builds: going back is naming an older one. The game follows the moving tag, and chapter 9's NWNX update
  is how a new build reaches it.

### The human playbook

You need tier 1 of this chapter. Tier 2 and chapter 9 are optional; step 29 says where they fit. The files are in
[`templates/nwnx`](../templates/nwnx).

`GAME` is the game host, and `you/unified` stands for your copy on GitHub.

#### 22. GENERIC. Decide what goes in a plugin of your own

A plugin of your own is the right home for anything specific to your world: your game rules, a system your module
leans on. If it would help any server, it belongs upstream instead: open a pull request on
[nwnxee/unified](https://github.com/nwnxee/unified), and when it's merged you no longer carry it. Bug fixes are
always worth sending.

Keeping your own code in its own folder under `Plugins/` means an upstream merge almost never touches your files.
Patches to upstream's own plugins are the ones that cost you work at every merge, so keep them few.

#### 23. ADAPT. Make your copy of NWNX

Change: whether it's public.

On GitHub, **Fork** [nwnxee/unified](https://github.com/nwnxee/unified). A fork of a public repository is public.
If you'd like yours private, make a new private repository instead and push upstream's source into it:

```sh
git clone https://github.com/nwnxee/unified.git && cd unified
git remote add mine git@github.com:you/unified.git
```

(you'll push in step 26). Then take out upstream's own workflows. They publish to upstream's accounts, need
secrets you don't have, and would fail on every push:

```sh
git rm -q .github/workflows/*.yml
```

#### 24. ADAPT. Add your plugin

Change: the plugin's name, from `Hello` to yours.

The example is the smallest plugin that does something you can see: `NWNX_Hello_Greet("Tester")` returns `Hello,
Tester, from your own NWNX plugin`. Copy it in:

```sh
cp -r ~/nwn-server-playbook/templates/nwnx/Plugins/Hello Plugins/
```

Three files make a plugin:

- `CMakeLists.txt` names the plugin and its source files. The build finds every folder under `Plugins/` by itself.
- `Hello.cpp` holds the functions. Each `NWNX_EXPORT ArgumentStack Name(ArgumentStack&& args)` is a function your
  scripts can call. `Config::Get` reads a setting: here `NWNX_HELLO_GREETING`, which changes the first word.
- `NWScript/nwnx_hello.nss` is what your scripts include. It pushes the arguments, calls the plugin by name, and
  pops the answer.

Upstream's plugins are the best examples of everything else: hooking the server, events, objects. `Util` and
`Reveal` are short ones to start with.

#### 25. GENERIC. Add the workflow

```sh
mkdir -p .github/workflows
cp ~/nwn-server-playbook/templates/nwnx/image.yml .github/workflows/image.yml
cp ~/nwn-server-playbook/templates/nwnx/image.Dockerfile image.Dockerfile
git add -A && git commit -m "Our own image workflow and our plugin"
```

[`image.yml`](../templates/nwnx/image.yml) compiles NWNX in upstream's builder image, pinned by its digest so
nothing changes under you. It keeps the compiler's cache between runs, which is what takes a build from ten minutes
to two. A pull request only compiles. A merge to `master` also packs the binaries, checks that the commit's tag isn't
in the registry yet, and builds the image from [`image.Dockerfile`](../templates/nwnx/image.Dockerfile): upstream's
base image (the game server and the libraries the plugins need, without NWNX) plus your build, made the same way
upstream makes its own image.

It needs no secrets. GitHub gives each run a short-lived token that may write packages to your own account.

The one line to keep current is `BASE_IMAGE`. Upstream rebuilds its base image about once a month, tagged by
commit; use the newest one for your game's build, listed on
[Docker Hub](https://hub.docker.com/r/nwnxee/nwnxee-base/tags).

#### 26. GENERIC. Push, and watch the first build

```sh
git push mine master
gh run watch -R you/unified
```

The first run took 11 minutes on the test, nearly all of it compiling from nothing; later runs took two to three.
When it's green, the run's summary lists the two tags it pushed, such as `ghcr.io/you/unified:4f54529` and
`ghcr.io/you/unified:build8193.37.17`.

If a push doesn't start a run, which happened on the test in a brand-new repository's first minutes, start one by hand:
**Actions**, **NWNX image**, **Run workflow**, or `gh workflow run image.yml -R you/unified`.

#### 27. ADAPT. Let the game host pull it

Change: nothing, if your package is public.

A package from a private repository is private too. To pull it, the game host needs a GitHub token that can only
read packages: on GitHub, **Settings**, **Developer settings**, **Personal access tokens**, **Tokens (classic)**,
with just **read:packages** ticked. Then:

```sh
ssh -t nwn@GAME 'docker login ghcr.io -u YOUR_GITHUB_NAME'
```

and paste the token as the password. Docker keeps it in `~/.docker/config.json` on the game host, readable only by
`nwn`, but not encrypted, which is why it should be a token that can do nothing else.

Or make the package public: on GitHub, your profile, **Packages**, the package, **Package settings**, **Change
visibility**. If you use chapter 9's NWNX update, public is simpler: the API asks the registry for the newest
build without logging in.

#### 28. GENERIC. Run the game on it, pinned

In `~/game/.env` on the game host, name the image by its **commit** tag, and switch your plugin on:

```
NWNX_IMAGE=ghcr.io/you/unified:4f54529
NWNX_HELLO_SKIP=n
```

Give the server your plugin's script file, the same way chapter 5 did for the SQL plugin:

```sh
scp Plugins/Hello/NWScript/nwnx_hello.nss nwn@GAME:
ssh nwn@GAME 'cd game && sudo cp ~/nwnx_hello.nss home/development/ && rm ~/nwnx_hello.nss && docker compose up -d && sleep 20 && docker compose logs nwserver | grep "Loaded plugin"'
```

You should see `NWNX_Hello.so` among the loaded plugins. Then ask it something from NWScript, in the console as in
chapter 5's step 6:

```
evalx WriteTimestampedLogEntry(NWNX_Hello_Greet("Tester"));
```

The server's log answers `Hello, Tester, from your own NWNX plugin`. That line came from your C++, called by a
script, inside your own image. In your module, `#include "nwnx_hello"` does the same for every script that needs
it; keep the file in your module's source beside the other `nwnx_*.nss` files, from the same commit as the image.

#### 29. GENERIC. Two tags, and when to use which

Every build pushes both:

- **The commit tag**, such as `4f54529`, names exactly one build, forever. The workflow refuses to push it twice:
  run it again on the same commit and it stops with `... is already in the registry. Commit tags are pushed once
  and never replaced.` before anything is built or pushed. So the name in your settings always means the same
  binaries, and going back is naming an older commit.
- **The moving tag**, such as `build8193.37.17`, is replaced by every new build.

Which one goes in the game's `NWNX_IMAGE`:

- **Without chapter 9's API**, use the commit tag. The version changes when you edit that line, exactly as in step
  11, and the line itself is your record of what runs.
- **With chapter 9's API**, use the moving tag in both the game and the API, as chapter 9's step 13 explains. The
  API's NWNX update pulls the moving tag and restarts the game, and its status shows which commit runs, because the
  workflow stamps each image with its commit (the `org.opencontainers.image.revision` label). Nothing moves the
  game but that update or a `docker pull` by hand.

Either way, keep the commit tags. They're the only history of your builds, so don't delete old package versions you
might want to go back to. To go back from the moving tag, put an older commit tag in the game's setting for a while,
as chapter 9 says.

#### 30. GENERIC. Keeping up with upstream

Every so often, and always when the game itself has a new build:

```sh
git fetch https://github.com/nwnxee/unified.git master && git merge FETCH_HEAD
```

in a branch, with a pull request, so the workflow compiles it first. If upstream's merge touches a workflow file
again, keep yours and remove theirs. For a new game build, also change `BASE_IMAGE` to upstream's base image for that
build. The moving tag's name follows the game build by itself, read from `CMakeLists.txt`.

#### 31. LAYONARA-ONLY. Four plugins

Our copy carries four plugins and a few patches to upstream's, and the plugin with our game rules will stay ours.
Please don't take our game rules as advice for yours: the numbers in them are tuned for one world.

### The agent playbook

If you work with an AI agent, [`playbooks/04-game-server-tier3.md`](../playbooks/04-game-server-tier3.md) has these
steps in a fixed shape it can follow. Making the repository, the registry token and any restart of the live game
stay with you.

### Lessons

- **A tag that can change isn't a record.** We once released a module whose scripts needed a plugin the live image
  didn't have yet (tier 1's first lesson, 2026-11-14). A commit tag that is never replaced is the smallest fix:
  the name says exactly which build runs, and the workflow makes sure it always will.
- **Keep your code in your own folder.** Upstream merges are easy when they never touch your files, and painful when
  they touch the same lines as your patches. That's why our game rules live in one plugin, and why our fixes to
  upstream's plugins go upstream.
- **Build on the same base upstream does.** I first built the image on top of upstream's finished image and swapped
  NWNX inside it. It worked, but it was 330 MB bigger, because the old NWNX stayed in the image's lower layer.
  Upstream's base image, without NWNX, gives the same image upstream ships.
- **A new repository's first pushes may not start a run.** On the test, GitHub took a few minutes to notice the
  workflow in a repository that had just received all of NWNX's history, and two pushes in that time started no
  run. Starting one by hand worked, and pushes after that started runs by themselves.

### Tested

On 2026-11-26, with upstream NWNX at commit `5af5459` (game build 8193.37.17), in a private GitHub repository
holding upstream's source, the example plugin and the workflow, and a game host in the state tier 1 leaves it (a
fresh Hetzner cloud server of the smallest shared type, with the database and a module):

- the first build: 11 minutes (compiling 9 minutes 48 seconds, the image a minute), and both tags pushed to a private
  GHCR package;
- the game host logging in with a read-only package token, pulling the image by its commit tag, and the game
  running on it, healthy, with `NWNX_Hello.so` loaded;
- the plugin answering from NWScript through `evalx`, and `NWNX_HELLO_GREETING` changing its answer to `Well met,
  Tester, ...`;
- the same commit built again, twice: once by re-running a finished run, once by starting a run by hand just after
  a merge's own run; both times the workflow refused before pushing, and the tag still pointed at the first build;
- a second commit: a new commit tag, the moving tag moved to it, the first commit tag unchanged, and the game still
  on its pinned build until its setting changed; moving the game to the new build and back took 9 seconds;
- the image built on upstream's base image, in 2 minutes 18 seconds: 1.15 GB, against 1.13 GB for upstream's own
  image, with the plugin loaded and answering; the game ran on it, healthy.

- the agent playbook as written, on a second fresh private repository: its first push started a run by itself six
  minutes later, the build took 10 minutes, and the game came up on the new commit tag with the plugin answering;
  then its roll back. Its first try found two faults, both fixed: it didn't wait long enough for a new repository's
  first run, and it changed the game's settings before checking that the image had arrived.

Not tested: chapter 9's NWNX update with this image (the API's update itself is tested in chapter 9), a public
fork made with GitHub's **Fork** button, an upstream merge into the copy, and a new game build.
