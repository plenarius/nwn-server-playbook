# Chapter 9. The operations API

**Status:** tiers 2 and 3 are written and tested. Tier 1 doesn't need it: with one machine and one person, you
restart by hand (chapter 4, step 10) and release with `release.sh` (chapter 16), and that's all a small server
needs. Tier 3, at the end, gives the API the game's own files so a website can show characters, items and names
the way the game words them.

## What you learn

Why one small service should be the only thing that operates your game server, and how to run one. Once there's a
team, more than one person and more than one tool want to restart the game, put a new module live or move to a new
NWNX version. Handing each of them SSH access to the game host works, but every one of those keys can do anything
there. The operations API turns those jobs into a handful of web requests, each opened by a key that can do only
what its holder needs.

The API is [nwn-ops-api](https://github.com/plenarius/nwn-ops-api), a small open-source project I extracted from the
one that runs Layonara. This chapter runs it on the control host from chapter 1's tier 2, through Coolify from
chapter 3, and points it at the game you moved into Coolify in chapter 4's tier 2. Its own README lists every
setting and route; this chapter is about running it in this guide's setup.

When you're done, you'll have:

- the API on the control host, reachable only on its private address, `10.77.0.1:8100`;
- four keys: one for a public status page, one for your staff's tools, one for you, and one kept in a safe;
- status, logs, restart with a countdown, stop and start, all as API calls;
- module and hak deploys from a staging folder, with a backup at the moment the game is stopped;
- NWNX updates in one call, once the game is on the right kind of image tag;
- notices on Discord, and, if you like, GitHub releases;
- the in-game countdown wired up for the day your module handles it.

Your Discord bot (chapter 10) and website (chapter 11) talk to the API; this chapter uses `curl`.

**Time:** about an hour. Building the image took 30 seconds on the test machine, and the API answered 30 seconds
after Coolify started it.

## What Layonara does

- **One service operates the game.** Our Discord bot, our website and our dashboards never touch the game host
  themselves; they ask the operations API. It runs on the control host, about a millisecond from the game host.
- **It has no Docker socket.** Everything it does to the game goes over SSH to the game host, as an ordinary deploy
  user, or through Coolify's API. A Docker socket in a container is root on its machine, and the API doesn't need
  it.
- **It reaches the game five ways:** SSH, the game's database, Redis, Coolify's API, and a few tables in the
  database that the game and the API both read and write. nwn-ops-api keeps the first four; the tables belong to
  our game systems, which are tier 3.
- **A restart is a countdown in the game.** The API publishes a command on Redis; the module announces it to
  players, counts down, saves and shuts the server down; Docker's restart policy brings it back.
- **A deploy moves the staged module and haks, then has Coolify make the container again.** That's what makes the
  new module name reach the game: a container restarted any other way keeps its old settings.
- **Keys come in groups.** Ours has eight; the website holds seven of them, each for one part of the site.
  nwn-ops-api has three, which is plenty for the operations it does.
- **The game runs on a moving image tag**, `latest` of our own NWNX build, and the API's NWNX update is how it
  moves: a new build reaches the game only when one of us presses the button.
- **It's much bigger than this.** About 400 routes, nine in ten of them for our game systems (characters, housing,
  crafting, reports). The part every server needs is about a tenth of it, and that tenth is nwn-ops-api.

## The human playbook

Each step carries a label: GENERIC (the same for any server), ADAPT (works once you change the things it names) or
LAYONARA-ONLY (something we do that you probably shouldn't copy).

You need chapter 3 done, and the game in Coolify from chapter 4's tier 2. The examples use `CONTROL` and `GAME` for
the two machines' public addresses, `10.77.0.1` and `10.77.0.2` for their private ones, and `nwn` as the deploy
user on both. The files for this chapter are in [`templates/ops-api`](../templates/ops-api).

### 1. GENERIC. Know what it reaches

| From the API to | How | For |
|---|---|---|
| The game host | SSH as `nwn`, with a key made only for the API | The container's state, the game's log, moving staged files, the image's version, `docker stop` and `docker pull` |
| Coolify | Its API, with a token | Making the game's container again (start, deploys, NWNX updates), and setting `NWN_MODULE` |
| Redis on the game host | Pub/sub, optional | The in-game countdown (step 10) |
| GitHub | Its API, with a token, optional | Releases and a look at what's waiting to go out (step 14) |
| Discord | A webhook, optional | Notices to players (step 15) |

Nothing reaches the API except over the private network. It needs no web name, no HTTPS, and no port open at the
provider: your bot and your website live on the control host or reach it through the tunnel.

Each part switches itself on when its settings are there, and a route whose part is off answers `503` naming the
settings it needs. So you can start with the game host and Coolify, and add Redis, GitHub and Discord later.

### 2. GENERIC. Folders for staged files on the game host

The API deploys what it finds in two staging folders inside the game's folder. Make them, owned by your deploy user
so you and your build jobs can copy files into them without `sudo`:

```sh
ssh nwn@GAME 'sudo install -d -o nwn -g nwn ~/game/home/modules/.staged ~/game/home/hak/.staged'
```

The game can't see either of them: it reads `home/modules` and `home/hak`, and a folder whose name starts with a dot
isn't a module or a hak to it. The rest of `~/game/home` was made by the game's container and belongs to root,
which is why the API moves files there with `sudo` (`SSH_SUDO=true` below). Chapter 1 gave `nwn` passwordless sudo.

### 3. GENERIC. Build the image on the control host

On the control host, as `nwn`:

```sh
git clone https://github.com/plenarius/nwn-ops-api.git ~/nwn-ops-api
cd ~/nwn-ops-api
docker build -q -t nwn-ops-api:$(git rev-parse --short HEAD) .
docker image ls nwn-ops-api
```

The image is named after the commit it was built from, such as `nwn-ops-api:409ae79`, for the same reason chapter 4
pins NWNX to a commit tag: the API changes version only when you build a new one and say so. Coolify won't rebuild
it on a merge, and that matters here more than anywhere: a countdown or a deploy in progress lives inside the API's
process, and a restart of the API in the middle of one loses it. Step 16 shows how to move to a newer version
calmly.

### 4. GENERIC. A key for the API to log in to the game host

Still on the control host:

```sh
mkdir -p ~/ops-api/ssh && chmod 700 ~/ops-api/ssh
ssh-keygen -q -t ed25519 -N '' -C nwn-ops-api -f ~/ops-api/ssh/id_ed25519
ssh-keyscan -q -t ed25519 10.77.0.2 > ~/ops-api/ssh/known_hosts
cat ~/ops-api/ssh/id_ed25519.pub
```

Add that last line to `~/.ssh/authorized_keys` on the game host, and check that the key works:

```sh
ssh -i ~/ops-api/ssh/id_ed25519 -o UserKnownHostsFile=~/ops-api/ssh/known_hosts nwn@10.77.0.2 'docker ps --format "{{.Names}}"'
```

You should see your game's containers. The `known_hosts` file is the game host's own public key: with it, the API
refuses to talk to a machine that isn't yours. The container runs as user 1000, which is `nwn` on a machine prepared
with chapter 1, so the files are readable to it as they are. If your deploy user has another number (`id -u`),
`sudo chown 1000` the two files.

Be aware of what this key can do: `nwn` can run `docker`, and that's as good as root on the game host. It's the
reason the key is made only for the API, lives only on the control host, and the API is never on a public address.

### 5. GENERIC. Four keys, and who gets which

Make four, each with `openssl rand -hex 32`, straight into your password manager:

| Key | Setting | Opens | Give it to |
|---|---|---|---|
| full | `OPS_API_KEY` | everything | nobody: it stays in the safe, for the day the others are lost |
| admin | `OPS_API_ADMIN_KEY` | everything | you, and your own tools: stop, start, deploys, NWNX, releases |
| team | `OPS_API_TEAM_KEY` | what the read key opens, plus the game's log, restart and cancelling a restart | your staff's bot or page |
| read | `OPS_API_READ_KEY` | status, modules and progress (without the log's lines), nothing that changes the game | your website's status page (chapter 11) |

The admin key opens as much as the full key does. Having two means either can be changed without the other: if the
admin key leaks, you make a new one and restart the API, and the full key is still there. A key that is known but
not allowed on a route gets `403` ("it needs the admin key"), and a wrong key `401`, so a caller can tell the two
apart.

The read key is the one to hand to anything the public can reach, like a status page. It can see whether the game
is up, who's on and since when, and that's all: it can't restart anything, and it doesn't get the game's log,
which names players and the addresses they connect from. The API refuses to start with a key shorter than 16
characters, and with a read key that's the same as one of the others, so a slip shows at once.

### 6. GENERIC. A Coolify token for the API

In Coolify: **Keys & Tokens**, **API Tokens**, **New Token**, as in chapter 3's step 12, but this time tick
**read**, **write** and **deploy**, not **Root**. That's what the API needs: read the game's settings, change
`NWN_MODULE`, and restart the service. On the test, a token with exactly those three did all of it. Coolify's
tokens can't be narrowed to one service, so this one can restart anything on your Coolify; it's another reason it
lives in the API only. Note its expiry date: after 30 days, unless you chose otherwise, the API's start and deploy
routes start failing.

You also need the game service's id: it's in the address of its page in Coolify, the part after `/service/`.

### 7. ADAPT. Create the service

Change: the image tag, the service id, and the addresses if yours differ.

In Coolify: **Projects**, make one called `ops-api`, and add a resource: **Docker Compose**, on the control host.
Paste in [`templates/ops-api/coolify.yaml`](../templates/ops-api/coolify.yaml). It names the image you built,
publishes the API on `10.77.0.1` only, and mounts the two SSH files from step 4.

Then the settings. [`templates/ops-api/ops-api.env.example`](../templates/ops-api/ops-api.env.example) has the
ones this guide's setup uses, with a word on each. Fill in your image tag, the four keys, the Coolify token and the
game service's id (twice), and paste them into the service's **Environment variables**, in **Developer View**. Leave
Redis, GitHub and Discord commented out for now. Two of them are worth a sentence:

- `COOLIFY_API_URL=http://10.77.0.1:8000` reaches Coolify from inside the API's container through the private
  address. The name isn't `COOLIFY_URL` because Coolify sets that one itself in every container (chapter 3,
  step 11).
- `DEPLOY_HOOK=/home/nwn/game/backup.sh` runs chapter 12's backup on the game host during every deploy, after the
  game is stopped and before it starts again: the most consistent backup you can take.

Deploy it. On the control host:

```sh
curl -s http://10.77.0.1:8100/health
docker logs $(docker ps -q --filter label=com.docker.compose.service=ops-api) 2>&1 | grep configured
```

You should see `{"status":"ok"}` and a line `configured: game, deploy, haks, logs, coolify`. And from your own
computer, `curl -s -m 5 http://CONTROL:8100/health` should time out: the API isn't on that address at all.

### 8. GENERIC. A first look

The rest of this chapter runs `curl` on the control host. A key on a command line ends up in your shell's history,
so read it from a file instead (`umask 077` first, then put the key in `~/.ops-team-key`):

```sh
API=http://10.77.0.1:8100/api/v1
team() { curl -s -H @<(printf 'Authorization: Bearer %s\n' "$(cat ~/.ops-team-key)") -H 'Content-Type: application/json' "$@"; }
team $API/server/status
team $API/server/modules
team "$API/server/logs?lines=5"
team $API/server/progress
```

`status` is the one your bot will ask most often: running or not, players online, the module, which NWNX build runs
and which is the newest, what's staged, and a countdown if one runs. `progress` is for following a restart or a
deploy: what the API is doing, the container's state, and the lines of the game's log that mark a start-up.

Then the refusal, so you've seen it once:

```sh
team -X POST -d '{}' $API/server/stop
```

`{"detail":"This key can't use this route (it needs the admin key)"}`. Make an `admin` function the same way, with
`~/.ops-admin-key`, and have a look at what the API says about itself:

```sh
admin $API/meta/systems
```

Every route with the key it needs, which parts are switched on and the settings each needs, and which keys are set.
Names only: no key, password or address is ever in it.

### 9. GENERIC. Restart with a countdown, and cancel it

```sh
team -X POST -d '{"wait_minutes": 5, "reason": "a new plugin"}' $API/server/restart
```

The answer comes at once; the countdown runs in the API. A minute is the least it will wait, half an hour the most.
At zero it stops the game and has Coolify make the container again; on the test the game answered players again
about 15 seconds later. Changed your mind?

```sh
team -X POST $API/server/cancel-restart
```

`{"ok":true,"message":"Restart cancelled"}`. A second restart while one is counting down is refused with `409`.

**Without the next step, players get no warning in the game.** The API says so in its answer (`"in_game": false`).
Your Discord notice (step 15) is then the warning, so give people time to read it.

### 10. ADAPT. The in-game countdown

Change: your module, which needs a handler for the restart command.

The countdown players can see is the module's job. The API publishes a message on Redis, and the module, through
NWNX's Redis plugin, announces the restart, counts down, saves and shuts the server down at zero. Docker's restart
policy then brings the same container back. The messages are written down in nwn-ops-api's
[restart contract](https://github.com/plenarius/nwn-ops-api/blob/main/docs/contracts/restart.md): two commands,
`restart` and `cancel_restart`, and a short reply the module stores in Redis. This guide's module template doesn't
have that handler yet. It's on its way, and until then this step is for those who write their own. Everything up to
step 9 works without it.

The pieces, once your module is ready:

1. **Redis on the game host.** In Coolify, in the `game` project, add a **Docker Compose** resource on the game host
   with [`templates/ops-api/redis.yaml`](../templates/ops-api/redis.yaml), and deploy it. It's published on
   `10.77.0.2` only.
2. **The game subscribes.** In the game service's settings: `NWNX_REDIS_SKIP=n`, `NWNX_REDIS_HOST=10.77.0.2`,
   `NWNX_REDIS_PUBSUB_CHANNELS=nwn:cmd`, and `NWNX_REDIS_PUBSUB_SCRIPT` set to your handler's script name (it
   defaults to `on_pubsub`). **Restart** the service, then copy the lines into `~/game/.env` too.
3. **The API publishes.** In the API's settings: `REDIS_URL=redis://10.77.0.2:6379`. Restart it.

**This Redis has no password, on purpose.** NWNX's Redis plugin has no setting for one, and its subscription can't
log in to a Redis that asks. I tried: the game's log said `Connected!` and Redis showed nothing subscribed. So the
private address is the lock. Anything on your private network can publish to it, and so restart your game; keep
that network to your own machines.

To check the wiring before your module is done, [`templates/ops-api/restart-standin.sh`](../templates/ops-api/restart-standin.sh)
plays the module's part: it answers each message as the contract says, counts down, and at zero restarts the game's
container. Copy it to the game host and run `./restart-standin.sh` there, then send a restart from the control host.
It's a test tool: players see nothing from it, so stop it with Ctrl-C when you're done.

One thing to know: the API answers `"in_game": true` before the game has replied. If the game refuses, for example
because a countdown is already running, the reason is in the API's log, not in the answer.

### 11. GENERIC. Stop and start

```sh
admin -X POST -d '{"wait_minutes": 10, "reason": "maintenance"}' $API/server/stop
admin -X POST $API/server/start
```

A stop counts down like a restart and then stops the container, which stays stopped. Start brings the game back
through Coolify. Both are admin-only: a stopped server doesn't come back by itself, so it's a decision for the
person who will be there to start it again.

### 12. GENERIC. Deploy a module from the staging folder

Give each release's module file a version in its name, such as `mymodule_1-02.mod`. Then the old one is still in
the live folder after a deploy, and going back is deploying the old name. The API reads the version from the name
(`1-02` becomes `v1.02` in its notices).

Copy the new module, and any changed haks and talk table, into the staging folders:

```sh
scp mymodule_1-02.mod nwn@GAME:game/home/modules/.staged/
scp myhaks/build/hak/*.hak myhaks/build/tlk/*.tlk nwn@GAME:game/home/hak/.staged/
```

`status` now lists them under `staged_modules` and `staged_haks`. Then, on the control host:

```sh
admin -X POST -d '{"module": "mymodule_1-02", "wait_minutes": 10}' $API/server/deploy
```

After the countdown the API stops the game, moves the staged module and haks into place (a talk table goes to
`home/tlk`), writes `NWN_MODULE=mymodule_1-02` into `~/game/.env`, Coolify's copy and Coolify's own settings, runs
the backup hook, and has Coolify make the container again. Follow it with `progress`; when `operations` is empty
and the container is `running:healthy`, check the log:

```sh
team "$API/server/logs?lines=3"
```

`Loading Module: mymodule_1-02`. On the test, a deploy with a one-minute countdown was done 77 seconds after the
request, and the game answered 16 seconds after that.

**Going back** is the same call with the old name and no countdown:

```sh
admin -X POST -d '{"module": "mymodule", "wait_minutes": 0}' $API/server/deploy
```

18 seconds on the test, from the request to a healthy game on the old module. Haks are different: their names
don't change between versions, so a deploy replaces them, and the API keeps no copy. For a release that changes
haks, keep the previous build's haks where you can find them (chapter 7's builds are a good place).

**How this fits with `release.sh`.** Chapter 16's script is still there, and still the right tool for a release
with database migrations (chapter 5), which the API doesn't run. The API's deploy is for the everyday case: a new
module, perhaps new haks, put live from a page or a button by whoever holds the admin key.

There's also a **full deploy**, `POST $API/server/full-deploy` with `{"wait_minutes": 10}`, which puts live
whatever staged differs from what runs: the newest staged module, the haks, and a new NWNX build (next step), all
after one countdown. With nobody online it skips the countdown.

### 13. GENERIC. NWNX updates, and the tag that makes them work

This one needs a decision first, and it's worth a few sentences, because it changes something chapter 4 told you.

The API's NWNX update pulls the image named in its own `NWNX_IMAGE` setting on the game host, and then has Coolify
make the game's container again. It doesn't change the game's own `NWNX_IMAGE` setting. So the update only does
anything if the game's setting names **the same tag** as the API's, and that tag is one that moves when NWNX
changes: a build tag, such as `nwnxee/unified:build8193.37.17`.

Chapter 4 put you on a commit tag, which never moves, so that your server changes version only when you edit a
line. That's still a good way to run a server. With the API, you trade it for something just as deliberate: the
version changes when someone with the admin key presses update, and the API shows you, beforehand, which build runs,
which is the newest and how many commits are between them. What you give up is the exact name of the version in
your settings: "build8193.37.17" means whichever build you last pulled, so write down the commit `status` shows
after each update. Going back means putting that commit tag in the game's setting for a while, which works because
the old image is still on the machine.

Nothing else moves the tag behind your back. On the test, a Coolify restart, a deploy and a reboot all kept the
build the host already had; only a pull fetches a new one, and only the API's update, or `docker pull` by hand,
does that.

To switch: set the game service's `NWNX_IMAGE` to the build tag that matches your game, and the same in
`~/game/.env` and in the API's settings. Restart the game. Then:

```sh
team $API/server/status
```

`nwnx_running` is the build the game runs, `nwnx_latest` the newest one in the registry under that tag, and
`nwnx.behind` how many commits apart they are, with a link to the changes. To fetch the new build without touching
the game, and then move to it:

```sh
admin -X POST $API/server/nwnx/pull
admin -X POST -d '{"wait_minutes": 10}' $API/server/nwnx/update
```

With players on, the update counts down first; with nobody on it goes straight ahead. On the test it took the game
from one build to the next in 27 seconds. If the game is still on a different tag, the update leaves it alone and
says why in the API's log (that check came out of this chapter's test; see "Lessons").

### 14. ADAPT. Releases on GitHub

Change: your repositories, and the tag format.

The API can show, per repository, the last release, what has been merged since, the CI runs and the open pull
requests, and it can make a release with GitHub's generated notes:

```sh
admin $API/server/repos
admin $API/server/release/preview
admin -X POST -d '{"repo": "module"}' $API/server/release
```

It needs a **fine-grained** GitHub token, for your module and hak repositories only, with **Contents** read and
write, and **Pull requests** and **Actions** read. Set `GITHUB_TOKEN` and, for example,
`REPOS=module=you/mymodule@main,haks=you/myhaks@main`.

If you use chapter 6's release workflow, two things to know. Its tags have three numbers, `v0.2.0`, and the API's
default has two, so set `RELEASE_TAG_REGEX=^v(\d+)\.(\d+)\.\d+$` and `RELEASE_TAG_FORMAT=v{major}.{minor}.0`.
And that workflow makes its own release when you push a tag, so keep releasing the way chapter 6 does, and use the
API to look before you do. I didn't test a release made through the API with a real token; see "Tested".

### 15. ADAPT. Notices on Discord

Change: your channel.

In Discord: the channel's **Edit Channel**, **Integrations**, **Webhooks**, **New Webhook**, **Copy Webhook URL**.
Put it in the API's settings as `DISCORD_WEBHOOK_URL`, with `SERVER_NAME` set to what players call your server.
The URL holds the webhook's password, so it belongs in your password manager too; the API never writes it to its
log.

The API posts when a restart or stop is scheduled, when a restart is cancelled, when an update is coming and when
it happens. Restart and NWNX notices go out only when someone is online, so nobody is told about a restart that
affects nobody. Deploys and cancellations are always announced.

### 16. GENERIC. Moving the API to a newer version

```sh
cd ~/nwn-ops-api && git pull
docker build -q -t nwn-ops-api:$(git rev-parse --short HEAD) .
```

Then look at `progress` and wait until `operations` is empty: no countdown, no deploy. Set `OPS_API_IMAGE` to the
new tag in the service's settings and **Restart** it. The old image stays on the machine, so going back is the old
tag and another restart. On the test the API was answering again within half a minute.

### 17. GENERIC. When the API itself is down

The game doesn't need the API to run; it only needs it to be operated. If the API is down, everything still works
the old way: the game service's **Restart** in Coolify, or chapter 4's commands on the game host. A new module can
still go live with `release.sh` (chapter 16). Then look at the API's logs in Coolify.

### 18. LAYONARA-ONLY. Everything else ours does

Our API also serves the website: character sheets, the vault, houses, crafting, reports from players. Those are
our game's own systems, and they're why ours has eight key groups and hundreds of routes. Tier 3 shows the part
every website can use: game data read through the same service. Please don't start there: the operations
above are the part that pays for itself first.

## The agent playbook

If you work with an AI agent, [`playbooks/09-ops-api-tier2.md`](../playbooks/09-ops-api-tier2.md) has these steps in a
fixed shape it can follow. The keys and tokens are made and placed by you, and every restart, stop, deploy, NWNX
update and release on a server people play on is your yes.

## Lessons

- **Don't redeploy the API while it's working.** A countdown or a deploy lives inside the API's process, with
  nothing to resume from. That's why the image here is built by hand and named after its commit, instead of
  redeploying itself on every merge, and why step 16 starts with a look at `progress`.
- **One tag for the game and the update.** While testing this chapter, the game was still on chapter 4's commit
  tag and the API watched the build tag. The update pulled the new build, restarted the game, said "NWNX updated",
  and the game came back on the old build. nwn-ops-api now leaves such a game alone and says why, and step 13 is
  the decision that avoids it.
- **A Redis password the game can't use.** I first wrote the Redis template with a password. NWNX's Redis plugin
  connected, logged `Connected!`, and was subscribed to nothing, because it has no way to send one. The template
  now has none, and the private address does the job.
- **Containers and the host firewall.** The test's stand-in for Discord first listened on a plain port of the
  control host, and the API's container couldn't reach it: `ufw` lets the tunnel in, not Docker's own networks.
  Real Discord is on the internet and Coolify's port is published by Docker, so neither is affected, but it's the
  first thing to check if a container can't reach something on its own host.

## Tested

On 2026-11-26, on two fresh Hetzner cloud servers of the smallest shared type, Ubuntu 26.04, in the state chapter
4's tier 2 leaves them: the game (NWNX `build8193.37.17`) and its database as a Coolify 4.7.5 service on the game
host, a nightly backup, and Coolify on the control host managing both over WireGuard.

- nwn-ops-api at commit `d43a6f8` (version 0.1.0, not yet released), built on the control host in 30 seconds;
  then at `409ae79`, the fixes from this test ([nwn-ops-api#2](https://github.com/plenarius/nwn-ops-api/pull/2)),
  through step 16's update. The repository was still private on the day, so the clone came from my own copy; you'll
  clone the public repository instead.
- The service from `coolify.yaml` with the settings of `ops-api.env.example`: healthy 30 seconds after it started,
  answering on `10.77.0.1`, refusing on `127.0.0.1`, and not reachable from outside.
- Every route in this chapter with the key it needs; the team key refused on stop (`403`), a wrong key and no key
  (`401`); the release and repository routes off (`503`) without a GitHub token.
- The read key, at `7b05e20` ([nwn-ops-api#3](https://github.com/plenarius/nwn-ops-api/pull/3)), on another fresh
  pair the same day: steps 3 to 6 of the agent playbook as written, with four keys (`copied 16`); status, modules
  and progress open to it, progress without the log's lines, the log and restart refused (`403`), and
  `started_at` in the status matching Docker's start time. Chapter 11's status page uses it.
- A Coolify token with only read, write and deploy: start, deploys and `NWN_MODULE` changes all worked with it.
- Restart without Redis: the container made again at zero and healthy about 15 seconds later; a second restart
  refused (`409`); a cancel, and a cancel with nothing to cancel.
- Stop with a countdown, a stop of a stopped server, start, and a start of a running server.
- A deploy of a staged module and a hak with a one-minute countdown: the files moved, `NWN_MODULE` set in both env
  files and in Coolify, the backup hook's backup, the game on the new module; going back to the old name in 18
  seconds; a full deploy of a newer staged module.
- The NWNX update on the moving tag: the host first held an older build under `build8193.37.17`, which a Coolify
  restart didn't change; then pull and update moved the game from `ed79330` to `5af5459` in 27 seconds. With the
  game on a commit tag instead, the API at `d43a6f8` restarted it for nothing, and at `409ae79` left it alone.
- Redis from `redis.yaml`: with a password, the game's plugin subscribed to nothing; without one, it subscribed.
  The in-game path with `restart-standin.sh` playing the module: a countdown, a refused second one, a cancel, and
  the container restarted at zero.
- Discord notices into a stand-in receiver on the control host: scheduled update, restarting, cancelled, updated.
- A reboot of both machines with an older build under the moving tag on the game host: the game came back on that
  same build, and the API came back healthy by itself.
- The agent playbook as written, from no API at all, after its own roll back had removed the first one: every
  step's check, the move to the moving tag, and Verify's restart and cancel.
- GitHub with a dummy token on a public repository: the preview and overview show GitHub's refusal, and a release
  is refused with `502` (it was a `500` before `409ae79`).

Not tested: a real Discord channel; a release made with a real GitHub token; the notices that need players online,
and anything else with a player connected; a module with its own restart handler; the dashboard forms by hand (the
services and settings were made through Coolify's API, which does what those pages do).

---

## Tier 3. Game data for a website

### What you learn

How to let your website show the game's own words: a character's sheet, an item as the game's examine window
describes it, the name behind a talk table number. nwn-ops-api has a small, optional part for this. It reads the
game's files itself (the base game, your module, your haks and your talk table), and it reads characters from the
server vault on the game host when it's asked. This part is about giving it those files, keeping them in step with
the live game, and deciding what a public page may show of a character.

When you're done, you'll have:

- the API's own copy of the game's files on the control host, kept in step every ten minutes by a small timer;
- five more read-only routes on the read key: talk table text, 2DA tables and rows, items, a player's vault folder
  and a character sheet;
- a staff route on the admin key that takes a character out of a vault without deleting anything;
- a clear idea of what in a character file is private, which chapter 11's character pages build on.

**Time:** half an hour. The first copy of the game's files took 5 seconds on the test, and a check with nothing new
takes about 3.

### What Layonara does

- **The same service serves the website.** Our character pages, item tooltips and recipe pages all come from the
  operations API, with the read key, the way chapter 11's status page does.
- **It reads the game's files the way the game does.** The haks in the module's order, then the module, then the
  base game. A page that shows an item shows the item a player would see, with the name from our talk table and the
  numbers from our 2DAs.
- **Its copy of the haks is the published one.** The API mounts the folder players download from, which is
  replaced whole at a release, never the folder a build writes into (see "Lessons").
- **Characters come from the vault.** Ours keeps an index of every character in its own database, refreshed every
  hour from the vault over SSH, so a list of a thousand characters doesn't mean a thousand file reads. A single
  character is read fresh, and the website keeps it five minutes.
- **The keys follow what they open.** Pages for the public use the read key. Players changing their own characters
  on the website go through a key of their own, and staff tools that change character files are on staff keys.
- **Taking a character out of play is a staff button,** with a dry run first. It renames the file in the player's
  vault folder, so nothing is lost and anything can be put back.

nwn-ops-api has the reading part, without the index or the picture renderer: a character's portrait comes back as
its name in the game's files, not as a picture.

### The human playbook

You need this chapter's tier 2 done, and chapter 7's tier 2: the control host has its own key to the game host
(chapter 7, step 14), and your haks and talk table are live on the game host.

#### 19. GENERIC. Know what it reads, and from where

| What | Where the API reads it | Fresh how |
|---|---|---|
| The base game: 2DAs, items, `dialog.tlk` | its own copy on the control host, from the image the game runs | copied again when the game's image changes |
| Your module, haks and talk table | its own copy on the control host, from the game host's live folders | every ten minutes (step 21), seen by the API within ten seconds |
| Characters | the game host's server vault, over SSH, when asked | each time; your website keeps them a few minutes |

The API reads files the way the game finds them: your haks in the order your module lists them (the first one wins),
then the module, then the base game. Every answer that comes from a file says which one, in `from`: a hak's name,
`module` or `base`. That's the quickest way to see which of two copies of a 2DA is the one the game uses.

The copies live on the control host because the API does. It never needs to touch the game's own folders for this,
and a copy that's ten minutes behind does no harm: a website showing yesterday's item name for a few minutes after a
release is fine.

#### 20. GENERIC. A version with the game data part

The game data part came after tier 2 was written. If your API is older, move it to a newer build as in step 16:

```sh
cd ~/nwn-ops-api && git pull
docker build -q -t nwn-ops-api:$(git rev-parse --short HEAD) .
```

Wait for `progress` to show no operations, set `OPS_API_IMAGE` to the new tag, and restart the service. The new
version switches the vault part on by itself (it uses `GAME_HOST` and `GAME_DIR`, which you already have), and the
API's log says `configured: ... vault`. The rest stays off until step 22.

#### 21. GENERIC. The API's copy of the game's files

On the control host, as `nwn`, put [`templates/ops-api/gamedata-sync.sh`](../templates/ops-api/gamedata-sync.sh)
and its two systemd files beside the API's other files, make the folder, and run it once:

```sh
cp ~/nwn-server-playbook/templates/ops-api/gamedata-sync.* ~/ops-api/
mkdir -p ~/ops-api/gamedata
~/ops-api/gamedata-sync.sh
```

The first time, it says `base game data copied from the image ...` and `module mymodule (1 changed), haks: 1
changed, talk tables: 1 changed`. What it did:

- **The base game** comes out of the image your game runs, `/nwn/data` inside it: the key and bif files and
  `dialog.tlk`, about 220 MB. It's copied over the private network, into a new folder that replaces the old one in
  a single step, and only when the game moves to a different image.
- **Your module** is copied under one fixed name, `module.mod`, whatever version is live: the script reads
  `NWN_MODULE` from the game's `.env`, the same line chapter 16's releases and step 12's deploys change.
- **The haks and talk table** are the live ones in `home/hak` and `home/tlk`, never the staged ones, which aren't
  live until a deploy. Each changed file goes into place at the end of the copy, so the API never reads half of one.

It changes nothing on the game host, and you can run it whenever you like. Then let a timer run it every ten
minutes:

```sh
sudo install -m 644 ~/ops-api/gamedata-sync.service ~/ops-api/gamedata-sync.timer /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now gamedata-sync.timer
systemctl list-timers gamedata-sync.timer
```

If your deploy user isn't `nwn`, change `User=` and the path in the `.service` file first. After a release, run the
script by hand if you'd like the website to catch up at once.

#### 22. ADAPT. Switch it on in the API

Change: nothing, if you used this guide's folders.

In Coolify, open the `ops-api` service and edit its compose file: take the `#` off the line

```yaml
      # - /home/nwn/ops-api/gamedata:/data/game:ro
```

so the folder is mounted read-only. (If your service was made before this chapter's tier 3, paste in the newer
[`coolify.yaml`](../templates/ops-api/coolify.yaml) first.) Then add the four settings at the end of
[`ops-api.env.example`](../templates/ops-api/ops-api.env.example):

| Setting | Value |
|---|---|
| `GAME_NWN_ROOT` | `/data/game/nwn` |
| `GAME_MODULE_FILE` | `/data/game/module.mod` |
| `GAME_HAK_DIR` | `/data/game/hak` |
| `GAME_TLK_DIR` | `/data/game/tlk` |

These are paths inside the API's container, not on the control host. You don't name your haks or your talk table:
the API reads them from your module's own list, in its order. Restart the service. Its log now says
`configured: ..., game_data, vault`.

#### 23. GENERIC. A first look

On the control host, with the read key in `~/.ops-read-key` the way step 8 keeps the others:

```sh
API=http://10.77.0.1:8100/api/v1
read_() { curl -s -H @<(printf 'Authorization: Bearer %s\n' "$(cat ~/.ops-read-key)") "$@"; echo; }
read_ $API/game/tlk/16777216
read_ $API/game/2da/classes/7?names=true
read_ $API/game/items/nw_wswls001
```

The first is the first line of your own talk table (custom talk table lines start at 16777216). The second is a
row of a 2DA, with the talk table text of its name columns; your hak's 2DAs answer here too, with `"from"` naming
the hak. The third is an item blueprint as the examine window shows it: name, weight, value, required level and
properties. Add `?identified=false` and it shows only what a player sees before the item is identified.

A file the API doesn't find is a `404`. If `from` names a copy you didn't expect, the order of the haks in your
module decides it, as it does in the game.

#### 24. GENERIC. Characters, and what's private in them

```sh
read_ $API/game/vault/QR7KX2PL
read_ $API/game/vault/QR7KX2PL/ariabrightwater
```

The vault folder is the player's: the game names it after their public CD key (or their player name, if your
server is set that way). The first route lists their characters' files, and the second is one character's sheet:
name, description, race, gender, deity, alignment, age, level and classes, experience and hit points, ability
scores, skill ranks, feats, what they wear with each item's examine panel, and the portrait's name. It's read from
the file the game last saved, each time you ask, in about a tenth of a second on the test.

Some of what's in a character file is the player's business, and some of it is a secret of your world's. Here's
how I'd sort it:

| In the file | Who should see it |
|---|---|
| Name, description, race, gender, deity, classes and level | the public, once the player says so: it's what the player wrote for others, or what anyone meeting the character could tell |
| What they wear | the public, if the player wants: it's visible in the game, but a quest reward's name can tell a story the player would rather keep |
| Ability scores, skills, feats, alignment, experience, hit points | the player, and the team. A build is a player's own work, and in a world with fights between players it's worth something to the other side |
| The vault folder and the file's name | the team only: the folder is the player's CD key |
| When the game last saved it | the team only: it's when the player last played |
| The pack and bags, gold, local variables, position | the team only. The API doesn't return them at all: they hold quest progress and where someone is right now |

The read key opens the sheet, because it's how a website reads a character, and the website then shows only part
of it. That makes your website the gate: its key can read any character in the vault, so the website must decide
whose sheet it shows, and which parts. Chapter 11's character pages do exactly that, and only for characters whose
players asked. Never hand the read key to anything that shows sheets as they come.

#### 25. GENERIC. Caching

The API keeps the game's files in memory and looks at them again at most every ten seconds, so a talk table line
or a 2DA row costs next to nothing. A character sheet costs an SSH call to the game host every time. That's cheap
(a tenth of a second), but a page visited a thousand times shouldn't make a thousand calls: whoever calls the API
keeps its answers. Chapter 11 keeps a sheet five minutes and an unknown name one minute. Five minutes is also how
long a changed character can take to show, and how long a page you've taken down can linger in a browser.

#### 26. ADAPT. Taking a character out of play

Change: the folder and file.

Sometimes a player asks you to remove a character, or a character has to leave play. The API renames its file in
the player's folder, so it's gone from their list in the game, and nothing is deleted:

```sh
admin -X POST -d '{}' $API/game/vault/QR7KX2PL/ariabrightwater/retire
admin -X POST -d '{"dry_run": false}' $API/game/vault/QR7KX2PL/ariabrightwater/retire
```

The first is a dry run: it says the new name, `ariabrightwater.bic.retired-20261126T182413Z`. The second does it.
It's refused while anyone is online, because a character who is logged in would be saved again under its old name.
To bring the character back, rename the file on the game host to its old name. It's on the admin key: the website
never gets it.

### The agent playbook

If you work with an AI agent, [`playbooks/09-ops-api-tier3.md`](../playbooks/09-ops-api-tier3.md) has these steps
in a fixed shape it can follow. Restarts of the API, and retiring any character, are your yes.

### Lessons

- **Copy what's live, from where it's live.** I first meant to read the haks from the control host's build folder,
  where chapter 7 builds them. But a build empties that folder first, and anything reading it then finds the base
  game's files instead of yours. We learned that the hard way: a picture renderer of ours once read the base game's
  table of placeables in the middle of a hak build. The script copies from the game host's live folders, and swaps
  each file in whole.
- **The game's image holds the game.** The base game's files the API needs are already in the image your game runs.
  Taking them from there means the API reads the very version the game does, with no download and no install.
- **A key that reads everything needs a gate.** The read key opens any character in the vault, because the API
  can't know which ones your players want shown. The website decides, and chapter 11 makes it decide by a list.
- **Leave out, don't hide.** The API never returns a character's pack, gold, local variables or position, so no
  page can show them by mistake. The website then picks, by name, the few fields it shows.

### Tested

On 2026-11-26, on two fresh Hetzner cloud servers of the smallest shared type, Ubuntu 26.04, prepared with chapters
1, 3 and 4 (tier 1 game with NWNX `ed79330` and its database as a plain Compose project, Coolify 4.7.5 on the
control host, WireGuard between them):

- nwn-ops-api at commit `fb5fea1`, its game data part
  ([nwn-ops-api#4](https://github.com/plenarius/nwn-ops-api/pull/4)), built on the control host from a copy of my
  own checkout, run as the Coolify service from `coolify.yaml` with the game data settings of step 22;
- the example hak and talk table of chapter 7 live on the game host, and a module with both in its list;
- `gamedata-sync.sh`: the first copy in 5 seconds (221 MB of base game data from the game's image), a run with
  nothing new in 3 seconds, a changed hak copied and answered by the API within 11 seconds without a restart, a new
  `NWN_MODULE` copied under the fixed name, a run with the game stopped (the base game left as it was), and a fresh
  copy when its record of the image was gone; then from the systemd timer;
- the agent playbook as written, from its roll back (timer, settings and copy removed) to Verify, with step 1
  skipped because the image already had the game data part;
- every game data route with the read key: a line of the custom talk table, a base game line, the hak's 2DA with
  `"from": "my_first_hak"`, a base game 2DA row with names, a base game item identified and not, a vault folder, a
  character sheet (0.07 to 0.2 seconds); an unknown folder `404`; retire refused on the read key (`403`), its dry
  run and a real retire with the admin key, and the character gone from the folder's list after it;
- the sheet's answer checked for what it leaves out: no pack, no gold, no local variable, no position.

The characters were made for the test, not played: two character files written with neverwinter.nim's `nwn_gff`
from real base game items (worn and in the pack), with gold, a local variable and a position added, and put in two
vault folders as the game would (owned by root, readable by all). No player logged in to make them, so the refusal
of a retire while someone is online wasn't tested, and the API read the game's own vault format only through those
files.

Not tested: the game as the Coolify service of chapter 4's tier 2 (the sync reads the same `.env` line and the same
container label either way); a deploy through the API followed by the sync (the module change was made by hand in
`.env`); a server whose vault folders are named after player names.
