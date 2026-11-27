# Chapter 7. Custom content: haks, the talk table and NWSync

**Status:** all three tiers are written and tested. Tier 2, further down, builds the content on the control host in
a pinned builder image, serves it from there, stages every new version and checks it before players can get it,
and cleans out old content. Tier 3, at the end, compiles models and serves content for builders' tools.

## What you learn

How to keep your custom content as files in git, build haks and a talk table from them, and let players' games
download exactly what your server needs when they join.

When you're done, you'll have:

- a repository where one folder is one hak, and your talk table is a text file;
- one command that builds them;
- your module listing its haks, and your server loading them;
- a download address, with a real certificate, that hands the content to players automatically. Nobody has to be
  sent a zip file again.

If your world uses no custom content yet, you can skip this chapter and come back the day it does.

**Time:** about half an hour. The web server had its certificate within seconds on the test, and a later update of
the content took the game away from players for 9 seconds.

## What Layonara does

- **Loose files in git.** Our content is 221,217 files, about 17 GB, in one repository. One folder is one hak. No
  packed hak is ever committed.
- **The module decides the order.** Which haks are used, and which one wins when two hold the same file, is the
  list in the module, not anything in the content repository.
- **The talk table is text.** It is a JSON file in git and is built again on every build.
- **Every merge builds everything.** A merge packs 57 haks and writes the download folder, in about 21 minutes on
  our build machine.
- **Players download through NWSync** from an HTTPS address. A player joining for the first time needs nothing but
  the game.
- **Nothing is ever half-written.** New haks are put in place by renaming, so neither a running server nor a
  player's download ever reads a file that is still being copied.
- **Old content is cleaned out carefully.** A tidy-up removes what no longer belongs, and it never removes what the
  live server is still handing out.

## The human playbook

Each step carries a label: GENERIC (the same for any server), ADAPT (works once you change the things it names) or
LAYONARA-ONLY (something we do that you probably shouldn't copy).

The files for this chapter are in [`templates/haks`](../templates/haks), the start of a content repository, and
four more files in `templates/game` for the web server: [`compose.web.yaml`](../templates/game/compose.web.yaml),
[`Caddyfile`](../templates/game/Caddyfile),
[`sites-available/nwsync.caddy`](../templates/game/sites-available/nwsync.caddy) and
[`.env.web.example`](../templates/game/.env.web.example). The module repository from chapter 6 gets one more small
tool, [`tools/set_haks.py`](../templates/module/tools/set_haks.py).

You need the tools from chapter 6, step 1. They include everything used here.

### 1. GENERIC. The three words

- A **hak** is a container file. It holds the models, textures, sounds and tables you've added to the game. The
  server needs your haks, and so does every player's game.
- The **talk table**, a `.tlk` file, holds your custom text: the names and descriptions that your content shows.
- **NWSync** is how the game fetches both by itself. Your server says "my content is at this address", and a
  joining player's game downloads what it doesn't have yet. The download is checked piece by piece, and a file that
  many servers share is only ever downloaded once.

### 2. GENERIC. Start the content repository

From this repository:

```sh
cp -r templates/haks ~/myhaks
cd ~/myhaks
git init -b main
```

It comes with one tiny example hak and a one-line talk table, so the rest of the chapter works before you've added
anything.

### 3. ADAPT. Put your content in

Change: the content.

One folder under `haks/` becomes one hak, with the folder's name. Inside a folder you may sort files into
subfolders as you please; they all end up in the same hak.

If you already have haks and a talk table, these turn them into files:

```sh
mkdir haks/my_models && (cd haks/my_models && nwn_erf -x -f /path/to/my_models.hak)
nwn_tlk -i /path/to/my.tlk -o tlk/my.tlk.json
```

Two rules about names, both old limits of the game. The names of haks and talk tables: at most 16 lowercase
letters, digits and underscores. The names of files inside a hak: at most 16 characters before the extension. The
build in the next step checks both and tells you which name it didn't like.

A word on what belongs here. Much community content comes with terms about sharing it. If any of yours says it may
not be passed on, keep this repository private.

### 4. GENERIC. Build

```sh
./build.sh
```

You should see one `packed build/hak/....hak` line per folder and one `built build/tlk/....tlk` line per talk
table. Then commit your files. `build/` stays out of git, as the built module did in chapter 6.

### 5. GENERIC. Tell the module

A module carries a list of the haks it uses and the name of its talk table. In the toolset that is under Module
Properties, Custom Content. In your module's repository it is one command:

```sh
cd ~/mymodule
cp /path/to/nwn-server-playbook/templates/module/tools/set_haks.py tools/    # if your copy doesn't have it yet
python3 tools/set_haks.py --tlk my_tlk my_first_hak
nasher pack --yes
```

Give the names without `.hak` and `.tlk`. **The order matters:** when two haks hold a file with the same name, the
one named first wins. `python3 tools/set_haks.py --show` prints what the module currently says.

### 6. GENERIC. Give the downloads a name, and open the web ports

Players' games need an address to download from. Add a second DNS record, `nwsync`, that points at the same machine
as `game` (chapter 2). Remember the lesson from that chapter and don't look the name up before it exists.

Web traffic also needs two ports that chapter 1 left closed:

- at your provider's firewall, allow TCP 80 and 443 inbound (chapter 1, step 3);
- on the server, tell the host firewall the same:

  ```sh
  ssh nwn@SERVER 'cd ~/host && sudo ALLOW_WEB=1 STEPS=firewall ./prepare-host.sh'
  ```

### 7. GENERIC. Write the download folder

Back in the content repository:

```sh
cd ~/myhaks
mkdir -p build/nwsync
nwn_nwsync_write --write-origins --description="My server's content" --path build/hak --path build/tlk build/nwsync ~/mymodule/mymodule.mod
```

This reads the module, finds the haks and the talk table it lists, and writes them into `build/nwsync` in the form
players' games download. The folder must exist first, which is what the `mkdir` is for. `--write-origins` adds a
small list of which hak each file came from, which players' games ignore; chapter 6's tests use it to rebuild your
haks from a download.

Inside, a file called `latest` holds one long name: the identity of the content you just wrote.

```sh
cat build/nwsync/latest
```

Every change to your content gives a new one, and the same content always gives the same one. Your server tells
players which one it wants, and that is how a player always gets the content that matches the server.

### 8. GENERIC. Start the web server

Copy the web server's files and the download folder to the server:

```sh
ssh nwn@SERVER 'mkdir -p game/sites game/nwsync game/site && sudo chown nwn: game/nwsync game/site'
scp templates/game/compose.web.yaml templates/game/Caddyfile templates/game/.env.web.example nwn@SERVER:game/
scp templates/game/sites-available/nwsync.caddy nwn@SERVER:game/sites/
rsync -a ~/myhaks/build/nwsync/ nwn@SERVER:game/nwsync/
```

Then, on the server, add the settings:

```sh
ssh nwn@SERVER
cd game
cat .env.web.example >> .env
nano .env
```

In `.env`, do three things: delete the older `COMPOSE_FILE=` line so only the new one remains, and put your own
name in the `NWSYNC_HOST` and `NWN_NWSYNCURL` lines. Don't start anything yet; the next step does it.

The web server is Caddy. I chose it because it gets a certificate for your name by itself and renews it by itself.
It serves one site for each file in the folder `sites` on the server, and the whole setup for this one is the few
lines in `nwsync.caddy`. The template keeps such files in `sites-available`, so that a site is only switched on
when you copy its file into `sites` and give it a name.

### 9. GENERIC. Put the content on the server and start

The server needs the haks, the talk table and the new module. From your own computer:

```sh
scp ~/myhaks/build/hak/*.hak ~/myhaks/build/tlk/*.tlk ~/mymodule/mymodule.mod nwn@SERVER:
```

and on the server, in `~/game`:

```sh
docker compose stop nwserver
sudo cp ~/*.hak home/hak/ && sudo cp ~/*.tlk home/tlk/ && sudo cp ~/mymodule.mod home/modules/
docker compose up -d
```

The game is stopped while its files are replaced, on purpose. A running server reads its haks all the time, and a
file must never change under it.

### 10. GENERIC. Check it

From your own computer:

```sh
curl -s https://nwsync.example.org/latest
```

It should print the same long name as `cat build/nwsync/latest` did. That one line proves the name, the
certificate, the web server and the folder.

On the server, the game says what it is handing out:

```sh
docker compose logs nwserver | grep NWSync
```

The last line should be `NWSync: We're now advertising` followed by the same name again. On the very first start
you may see `Failure to get latest manifest hash` once or twice above it. That is the game asking a few seconds
before the web server had its certificate. It asks again by itself.

To see that the server really loaded your content, ask it at the console (chapter 4, step 7). With the example
content:

```
eval WriteTimestampedLogEntry(Get2DAString("ex_notes", "Note", 0));
eval WriteTimestampedLogEntry(GetStringByStrRef(16777216));
```

The first line reads a table from the example hak, the second reads the first line of the example talk table. Both
answers appear in `docker compose logs nwserver`. The number is worth remembering: your own talk table's lines
start at 16,777,216, so its line 0 is that number, its line 1 the next, and so on.

And then the real thing: join with the game. It downloads your content, shows you what it's doing, and lets you in.

### 11. GENERIC. Changing your content later

The order below keeps every player on content that matches the server, at every moment:

1. Change the files, run `./build.sh`, and if the list of haks changed, run the commands from step 5 again.
2. Write the download folder again (step 7) and send it with the same `rsync` (step 8). **Do this first.** It only
   adds files. The running game keeps handing out the old content, which is still there, so nothing changes for
   anyone yet.
3. Copy the haks, the talk table and the module, stop the game, replace the files and start it (step 9). When the
   game comes back, it hands out the new content.

On the test, step 3 took the game away for 9 seconds.

Old content stays in the download folder. That's harmless, apart from the disk space, and tidying it safely is a
tier 2 subject.

### 12. LAYONARA-ONLY. Seventeen gigabytes

Our content repository is big enough to need its own rules: small partial checkouts, a build machine, and a build
that takes about 21 minutes. None of that is needed to start. A handful of haks builds in seconds on your own
computer, as it did on the test.

## The agent playbook

If you work with an AI agent, [`playbooks/07-haks-nwsync.md`](../playbooks/07-haks-nwsync.md) has these same steps
in a fixed shape it can follow. It stops and asks before it makes a DNS record, and before anything that restarts a
game players might be on.

## Lessons

These are the things that went wrong for us, written down so they don't have to go wrong for you. The dates are
when they happened to Layonara.

- **Build the talk table every time (2026-11-05).** Our talk table lived in git as text, as it should. But the
  build was still shipping a compiled copy that someone had committed back in 2024, so for a long while no text
  change reached a single player, and nothing failed to tell us. Since that day the build makes the table from the
  text, every time. `build.sh` does the same, and it is why no built file is ever committed.
- **Never change a file under a running server.** We put new haks in place by renaming, which swaps a whole file in
  one instant. Step 9 gets the same safety the simple way, by stopping the game for a few seconds.
- **Publish before you switch.** New content goes into the download folder first, while the old stays. Only then
  does the server change over. Done the other way round, there is a moment when the server asks players for content
  that isn't there yet.
- **The order of haks is part of your module.** It lives in the module's list, where it is reviewed and versioned
  with everything else, and not in the content repository.

## Tested

On 2026-11-18, with neverwinter.nim 2.3.2 and Caddy 2.11, on a fresh Hetzner cloud server of the smallest shared
type that had been through chapters 1, 4, 5 and 6, and a temporary name in our own domain:

- the build: the example hak and talk table, a hak name that is too long, a file name that is too long, and files
  in a subfolder;
- turning an existing hak and an existing talk table back into files;
- `set_haks.py`, and that its changes survive a build and an unpack unchanged;
- writing the download folder, sending it, and the web server getting a real certificate within seconds;
- the download address from outside: `latest`, the list it names, and each content file; plain HTTP is sent on to
  HTTPS, and folders can't be listed;
- the game finding `latest` by itself and advertising it, including the first failed tries before the certificate
  existed;
- the server reading a table from the example hak and a line from the example talk table;
- two updates of the content, the second in the order of step 11: the running game kept advertising the old content
  until its restart and the new one after it;
- a player's game joining by name: it was sent to download the content, came back four seconds later and was let
  in.

Not tested: a separate `nwsync` name beside the `game` name (one name served both in the test), large content, and
the certificate's renewal, which is due only after two months.

---

## Tier 2. Content built and served from the control host

### What you learn

How to move the building and the serving of your content off the game host and onto the control host from chapter
1's tier 2, and how to release new content in two separate moves: first stage it, where you can check it and
players can't see it yet, then promote it. The game host then only runs the game.

When you're done, you'll have:

- your content repository cloned on the control host, which builds it;
- a **builder image**: the content tools at one pinned version, checked against a checksum, in which every build
  runs;
- the download address served by Coolify on the control host, with its own certificate;
- [`templates/content/publish.sh`](../templates/content/publish.sh): one command from a merged change to a
  **staged** version, downloaded and checked over HTTPS the way a player's game would fetch it, with its files
  waiting on the game host;
- [`promote.sh`](../templates/content/promote.sh): one command that releases the staged version, and with
  `--back`, one that goes back to the version before;
- old versions removed only when nothing can still need them, the one the live game hands out above all;
- a game host with no web server and nothing open but the game.

Players notice none of it until you promote, and the release itself is the same few seconds as before: on the
test the whole promote, with its backup and the restart, took about 10 seconds.

### What Layonara does

- **A merge builds everything on our build machine,** never on the game host: 57 haks and the download folder, in
  about 21 minutes.
- **The download folder is served by a Coolify service** with its own name and certificate.
- **The game host receives finished files** and swaps them in when we release.
- **The build runs in a pinned image.** Every tool in it is downloaded at a fixed version and checked against a
  SHA-256 checksum, and the image refuses to build if a tool reports another version.
- **New haks are staged.** They wait in a side folder on the game host and go into place only in the release,
  together with the module, before the restart.
- **The tidy-up keeps what the live game hands out.** It reads the version from the game itself before it removes
  anything.

### The human playbook

You need chapter 1's and chapter 3's tier 2, and chapter 4's tier 2 is a good idea first, so that Coolify already
runs the game. The examples use `GAME` for the game host's public address and `CONTROL` for the control host's. The
game host's private address is `10.77.0.2`, as in chapter 1.

The new files are in [`templates/content`](../templates/content):

- [`builder/Dockerfile`](../templates/content/builder/Dockerfile) and
  [`builder/nwsync-check`](../templates/content/builder/nwsync-check), the builder image;
- [`publish.sh`](../templates/content/publish.sh), [`promote.sh`](../templates/content/promote.sh) and
  [`prune.sh`](../templates/content/prune.sh), with the settings they share in
  [`content.env.example`](../templates/content/content.env.example) and [`lib.sh`](../templates/content/lib.sh);
- [`downloads.yaml`](../templates/content/downloads.yaml) with its [`Caddyfile`](../templates/content/Caddyfile),
  the downloads service.

#### 13. GENERIC. Know what moves

- **The build** moves to the control host. It clones your content repository and builds from it, exactly as
  `build.sh` does on your own computer.
- **The download folder** moves to the control host, and the name players download from moves with it. The game
  doesn't need to know: it asks the same name as before.
- **The game host keeps its haks and talk table.** The game needs them on its own disk. `publish.sh` sends them
  across the private network, and `promote.sh` releases them with chapter 16's `release.sh`.
- **The tools move into an image.** Nothing is installed on the control host itself, and the version of the tools
  changes only when you change one line.

#### 14. GENERIC. A key and the repository on the control host

On the control host, as `nwn`, make the control host its own key:

```sh
ssh-keygen -t ed25519 -N "" -C "nwn@control" -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub
```

That key does two jobs:

- **On GitHub,** in your content repository: **Settings**, **Deploy keys**, add it, **read-only**. The control host
  can then read the repository, and nothing else on GitHub.
- **On the game host,** add the same line to `~/.ssh/authorized_keys`, so the control host can send it files and
  run the release:

  ```sh
  ssh nwn@GAME 'cat >> ~/.ssh/authorized_keys'   # paste the line, then Ctrl-D
  ```

Then, back on the control host, check both and clone:

```sh
ssh nwn@10.77.0.2 hostname        # answer "yes" to the first-time question
ssh-keyscan github.com >> ~/.ssh/known_hosts
git clone git@github.com:you/myhaks.git ~/myhaks
```

#### 15. ADAPT. The download folder, the scripts and the builder image

Change: the address in `content.env`.

The control host starts with everything the game host serves today, so no player's download breaks when the name
moves. On the control host:

```sh
mkdir -p ~/nwsync ~/content
rsync -a nwn@10.77.0.2:game/nwsync/ ~/nwsync/
cat ~/nwsync/latest
```

From your own computer, the scripts, the downloads service's settings file and the builder image's files:

```sh
scp -r templates/content/* nwn@CONTROL:content/
```

The `Caddyfile` has to be there before the downloads service starts. Otherwise Docker makes an empty folder in its
place, and the service won't start.

Back on the control host, the scripts' one setting, the address players download from:

```sh
cd ~/content
cp content.env.example content.env
nano content.env        # NWSYNC_URL=https://nwsync.example.org, your own name
```

Now the **builder image**. It holds the neverwinter.nim tools, the same ones you use at home, at one version. The
[`Dockerfile`](../templates/content/builder/Dockerfile) downloads them and checks the download against a checksum
written in the file, so a changed or damaged download stops the build instead of reaching your players. Build it and
use it once:

```sh
docker build -t nwsync-builder:2.3.2 ~/content/builder
docker run --rm --user "$(id -u):$(id -g)" -v ~/myhaks:/src nwsync-builder:2.3.2 /src/build.sh
```

The image took 22 seconds to build on the test, and the build should pack your haks and the talk table, as it does
at home. You won't usually run either command again: `publish.sh` does its work in the image, and builds the image
again by itself if it's ever missing, for example after a clean-up of unused images.

#### 16. ADAPT. The downloads service

Change: the two paths in the file, if your deploy user isn't `nwn`.

In Coolify: a project (I called mine `web`), add a resource, **Docker Compose**, with the **control host** as its
server, and paste in [`templates/content/downloads.yaml`](../templates/content/downloads.yaml). On the service's
page, give it its domain: your download name with `https://` in front, such as `https://nwsync.example.org`.
**Don't deploy yet.**

At the control host's provider firewall, open TCP 80 and 443 to everyone. Coolify's proxy needs both: 80 to get its
certificate, 443 for the downloads.

#### 17. GENERIC. Move the name, then deploy

The order matters. The proxy asks for the certificate the moment the service starts, and the request only works if
the name already points at the control host.

1. Point your download name at the control host's public address, as in chapter 2. Give it a few minutes, or check
   it at the source as chapter 2 shows.
2. Deploy the service.
3. Check it from your own computer:

   ```sh
   curl -s https://nwsync.example.org/latest
   echo | openssl s_client -connect nwsync.example.org:443 -servername nwsync.example.org 2>/dev/null |
     openssl x509 -noout -issuer
   ```

   The first should print the same version as `~/nwsync/latest`, and the second Let's Encrypt.

If you deployed first, the first certificate request fails. Once the name points at the right machine, `docker
restart coolify-proxy` on the control host makes the proxy try again; on the test that fixed it.

#### 18. GENERIC. Restart the game once, and watch it find the new address

Each time the game starts, it fetches `latest` from the download name. Restart it now, at a quiet moment, while
you're watching. In Coolify that's the game service's **Restart**. Then on the game host:

```sh
docker logs $(docker ps -q --filter label=com.docker.compose.service=nwserver) 2>&1 | grep NWSync | tail -2
```

You should see it fetch from your download name and say `We're now advertising` with the version from step 17.

**Never restart the game while the download address isn't working.** A game that can't fetch `latest` won't start:
on the test, Docker restarted it 29 times while the new address had no certificate yet. It came back by itself as
soon as the address worked again.

#### 19. GENERIC. Switch off the game host's web server

The game host no longer serves anything on the web. On the game host:

```sh
cd ~/game
docker compose stop caddy && docker compose rm -f caddy
nano .env      # set COMPOSE_FILE back to compose.yaml:compose.db.yaml
```

Now Coolify's own proxy. With Caddy gone, Coolify starts its proxy on the game host the next time it deploys or
restarts the game: on the test it was running a minute after the game's restart, on ports 80 and 443. So stop it
now, on the game host's **Proxy** page in Coolify: **More actions**, **Stop Proxy**, and confirm, as in chapter 3's
step 6. It then stays stopped. On the test, a later restart of the game left it off.

Then close TCP 80 and 443 at the game host's provider firewall. Leave `~/game/nwsync` where it is for now. It's
your copy until you've released from the control host once.

If your game host still serves a website from tier 1, keep Caddy running for now, remove only `sites/nwsync.caddy`
and run `docker compose up -d caddy`. Chapter 11's tier 2 moves the website.

#### 20. GENERIC. Know why releases come in two moves

The game reads `latest` from your download address **every time it starts**, and hands out whatever version that
names. Not only when you release: also when it crashes and Docker starts it again, or when the machine reboots at
night for an update.

So `latest` must only ever name content whose haks are already on the game host. If a new version were named in
`latest` while the game host still had the old haks, the next unplanned start would send every joining player
content that doesn't match the server's.

That's why, from here on, a release has two moves:

- **Stage.** `publish.sh` builds the new version and writes it beside the others in the download folder. `latest`
  is not touched. The script then downloads the new version from your real address, over HTTPS, as a player's game
  would, and checks every file. The haks, the talk table and the module go to `~/incoming` on the game host and are
  checked there too. Players can't see any of it: nothing tells their games it exists.
- **Promote.** `promote.sh` moves `latest` to the staged version and runs the release on the game host. Both
  change in the same few seconds, in that order, so the game reads the new version when the release restarts it.

#### 21. GENERIC. Stage a new version

When a change to your content is merged, on the control host:

```sh
~/content/publish.sh ~/mymodule.mod
```

The module file is the one you're about to release: fetch it as in chapter 16's step 6 and copy it to the control
host. Its list of haks decides what goes into the new version, and it travels to the game host with the content.

On the test, with the example content, it printed:

```
packed build/hak/my_first_hak.hak (1 files)
built build/tlk/my_tlk.tlk
written 8fbb20b5950961620278816e3de6a2b1e3fccb74
Entries: 2 Size: 171B
checked: https://nwsync.example.org hands out 8fbb20b5950961620278816e3de6a2b1e3fccb74 completely
sent 3 files to 10.77.0.2:incoming, checked
staged 8fbb20b5950961620278816e3de6a2b1e3fccb74
players still get a5f67333db8d4f7655fcbff94121e8d3e4d497d5. To release: /home/nwn/content/promote.sh
```

The last line is the one to read: players still get the old version. If any check fails, the script stops, says
which one, and stages nothing. A new run replaces whatever was staged before, in `~/incoming` too.

If the game host has chapter 6's staging copy, `publish.sh` also gives it the new content, so you can try the two
together before your players see either; it then prints one more line, `staging has the same content`. Chapter
16's tier 2 shows the one setting staging needs for that, and where it fits in a release.

You can repeat the download check by hand at any time, for any version, on the control host or anywhere else you've
built the image:

```sh
docker run --rm nwsync-builder:2.3.2 nwsync-check https://nwsync.example.org 8fbb20b5950961620278816e3de6a2b1e3fccb74
```

It prints the number of files and their size, or what went wrong. On the test it noticed a missing file and a
damaged one.

#### 22. GENERIC. Promote it

At a quiet moment, when you'd release anyway (chapter 16's steps 1 to 4 still apply), on the control host:

```sh
~/content/promote.sh
```

It moves `latest` to the staged version, then runs `release.sh` on the game host for you: the backup, the swap,
the restart. Then it asks the game which version it hands out, and should say the staged one:

```
latest is 8fbb20b5950961620278816e3de6a2b1e3fccb74 (was a5f67333db8d4f7655fcbff94121e8d3e4d497d5)
backup made: backups/20261126-144236 (16K)
game stopped
installed home/hak/my_first_hak.hak
installed home/modules/mymodule.mod
installed home/tlk/my_tlk.tlk
game started
the game is healthy again
the game hands out 8fbb20b5950961620278816e3de6a2b1e3fccb74
kept: latest, the staged one, the one to go back to, the game's 8fbb20b5950961620278816e3de6a2b1e3fccb74, ...
```

This replaces chapter 16's steps 5 to 7 whenever content changes. A release of the module alone still goes the
chapter 16 way.

If the release fails, the script says so and tells you the command that goes back.

#### 23. GENERIC. Going back

If the new content turns out wrong, on the control host:

```sh
~/content/promote.sh --back
```

It points `latest` at the version from before the last promote, and runs `release.sh --undo` on the game host,
which puts back the haks, the talk table and the module that release replaced. On the test that took 9 seconds,
and the game handed out the earlier version again.

Going back works once, for the last promote. Two things to know:

- `--back` uses `release.sh --undo`, which puts back what the **last** release replaced. If you released a module
  alone since the promote, it would put back that module and not the content. In that case, don't use `--back`:
  stage the older content again, as in the next point.
- To go back further, stage the older content again: revert the change in git and publish. The same content always
  gives the same version, so players who still have it download nothing.

#### 24. GENERIC. The tidy-up

After every promote, `promote.sh` runs [`prune.sh`](../templates/content/prune.sh). It removes an old version only
when every one of these holds:

- it isn't among the newest three;
- it isn't what `latest` names, nor the staged version, nor the one `--back` would go back to;
- it isn't what the game says it is handing out right now;
- it's more than 7 days old.

Content files that no remaining version uses go too, once they're 7 days old. If the script can't ask the game
which version it hands out, for example because the game is stopped, it removes nothing and says so. Only one of
the three scripts runs at a time.

You shouldn't need to run it yourself. If you do, it's `~/content/prune.sh`. The numbers are settings in
`content.env` (`KEEP` and `MIN_AGE_DAYS`); a setting that file doesn't set can also go in front of a command, as in
`KEEP=5 ~/content/prune.sh`.

#### 25. GENERIC. A new version of the tools

The image is named after the version of the tools in it. When neverwinter.nim releases a new version and you want
it:

1. In `~/content/builder/Dockerfile`, change `NWN_TOOLS_VERSION`, and `NWN_TOOLS_SHA256` to the checksum of the new
   zip file (`sha256sum` of the zip you downloaded from the release page).
2. In `content.env`, set `IMAGE=nwsync-builder:` and the new version.
3. Stage as usual. `publish.sh` builds the new image first.

The old image stays until you remove it (`docker rmi nwsync-builder:2.3.2`), so going back is changing the line in
`content.env` back.

#### 26. LAYONARA-ONLY. Seventeen gigabytes, again

Our build runs on its own machine and takes about 21 minutes, because of the size of our content. The steps above
are the same; ours just take longer, and our build machine has a disk sized for two copies of everything.

### The agent playbook

If you work with an AI agent, [`playbooks/07-haks-nwsync-tier2.md`](../playbooks/07-haks-nwsync-tier2.md) has these
steps in a fixed shape it can follow. It stages by itself, and asks before it moves the name, before it promotes or
goes back (both restart the game), and before any tidy-up run by hand.

### Lessons

- **Each move costs a certificate, and they're rationed.** Let's Encrypt gives at most five certificates for the
  same name in a week. Testing this chapter, I used up all five for one name in a single day of moving it back and
  forth, and had to finish under a new name. One move is no problem. Just don't practise on your real name.
- **Move the name before you deploy.** Covered in step 17, and learned the obvious way.
- **The game depends on its download address.** A game told where to download from and not which version reads
  `latest` at every start, and won't start without it. Keep the address working before you restart, and check it
  first when the game won't start.
- **Never tidy away what the live game hands out.** The tidy-up asks the game itself, because a player joining
  right now is downloading exactly that version. We keep it, whatever its age.
- **Give the control host its own key.** A read-only deploy key reads one repository and nothing else, and the game
  host accepts the same key for the files. Nobody's personal key has to live on a server.
- **`latest` is read at every start, not only at releases.** A game that crashes, or a machine that reboots for an
  update at night, starts again and hands out what `latest` says. That's why `latest` moves only in the promote,
  together with the haks, and never while a version is merely built.
- **The tool's own `latest` isn't careful enough to share.** Reading neverwinter.nim 2.3.2 for this chapter
  (2026-11-26), I saw that its writer updates `latest` a moment before it writes the manifest that `latest` names.
  `publish.sh` tells it not to touch `latest` (`--no-latest`), and `promote.sh` writes `latest` itself, in one
  step, by renaming.
- **Check the way players fetch.** A version can be complete on the control host's disk and still not downloadable:
  the downloads service stopped, a wrong address, a missing file. On the test, with the service stopped, the check
  failed with the web server's error, and nothing was staged. Only a download from the real address proves it.
- **The tools' fetch tool can't do HTTPS (2026-11-26).** The released `nwn_nwsync_fetch` is built without HTTPS
  support, so `nwsync-check` lists the files with `nwn_nwsync_print`, downloads them with `aria2c`, and lets
  `nwn_nwsync_print --verify` compare every checksum.

### Tested

On 2026-11-18, with Coolify 4.7.5, neverwinter.nim 2.3.2 and Caddy 2.11, on a pair of fresh Hetzner cloud servers
of the smallest shared type: a game host in its tier 1 state with downloads served by tier 1's Caddy, the game then
moved into Coolify as in chapter 4's tier 2, and a control host from chapter 3. A throwaway private repository
stood in for the content repository, and a temporary name in our own domain for the download name.

- the tools, the key as a read-only deploy key and on the game host, the clone and a build on the control host;
- the downloads service: the name moved, then the service deployed, and a Let's Encrypt certificate at once;
  `latest`, a manifest and plain HTTP sent on to HTTPS from outside, folders not listed, `latest` not cached;
- the game restarted through Coolify, fetching `latest` from the new place and advertising it;
- Caddy stopped on the game host; Coolify then started its own proxy there at the game's next restart; stopped in
  the dashboard, it stayed off through another restart;
- the first version of `publish.sh`, which also tidied up, with no change and with a merged change; the files sent; `release.sh` in 8 seconds; the game
  advertising the new version;
- the tidy-up, with every file aged to 10 days: three more publishes removed the two oldest versions one at a time,
  kept the version the game was handing out although it was older than the newest three, removed the content files
  only the removed versions used, and the kept version still downloadable;
- a reboot of the control host: the downloads back by themselves within about two minutes;
- on an earlier pair, the deploy-first order: the first certificate request failed, and the game, restarted then,
  stopped and was restarted by Docker 29 times until the address worked again.

Not tested: the downloads service's dashboard forms by hand (the service was made through Coolify's API), a publish
while another runs, and a content repository the size of ours.

The builder image, staging, promoting, going back and the tidy-up after them (steps 14, 15 and 20 to 25) were
tested on 2026-11-26, with Coolify 4.7.5, neverwinter.nim 2.3.2 in the image on `ubuntu:24.04`, Docker on Ubuntu
26.04, on another pair of fresh Hetzner cloud servers of the smallest shared type. They were brought to the state
the steps above leave them in: the downloads service on the control host under a temporary name in our own domain,
with a real certificate, and the game advertising from it. The game ran with tier 1's Compose rather than in
Coolify, which `release.sh` handles the same way. A plain git repository on the control host stood in for the
content repository on GitHub.

- the image: built in 22 seconds, 284 MB; the first build in it; built again by `publish.sh` when missing;
- staging: a changed table in the example hak; the new version written while `latest` and the game kept the old
  one; the check over HTTPS from the control host and again from outside; the files on the game host checked;
- a restart of the game while a version was staged: it kept handing out the old version;
- the check failing: with a missing file and a damaged file (against a local copy), and with the downloads service
  stopped, when `publish.sh` stopped and staged nothing, and `promote.sh` then refused;
- promoting, three times: `latest` moved, `release.sh` run over SSH, the game handing out the new version, in 9 to
  11 seconds in all, backup and restart included;
- the tidy-up after the second release, with every file aged to 10 days and `KEEP=1`: the oldest version and the
  content file only it used were removed, and the live version and the one to go back to were kept; with the game
  stopped it removed nothing;
- going back: `latest` and the files back to the version before in 9 seconds, the game handing it out, and that
  version still downloading completely; a second `--back`, and a promote with nothing staged, both refused.

Not tested: a release that fails halfway inside `promote.sh`, a new version of the tools, and the image being
removed by Coolify's own clean-up (removed by hand instead).

## Tier 3. Compiled models, and NWSync builders can read

### What you learn

How to have the build compile your models, and how to let your builders' tools take your content straight from
NWSync instead of from hak files you hand around.

The game reads models in two forms: **ASCII**, the text a modelling tool exports, and **binary**, what the game
itself ships. Both work, but a binary model loads faster and is smaller to download, and compiling one first is
also the moment to find out it's broken. Doing that by hand for every model, every time, doesn't last once many
people add content. So here the build does it, with [cleanmodels](https://github.com/plenarius/cleanmodels), a
free model checker and compiler I maintain.

When you're done, you'll have:

- a builder image with cleanmodels in it, pinned and checked like the other tools;
- every ASCII model in your haks checked and compiled to binary in the build, and a broken model refused before
  anything is packed, with the file and the line in the message;
- a **model cache**: a compiled model is kept, so the next build compiles only the models that changed;
- an **origins file** beside every version you publish, listing which hak each file came from, and a small
  script that reads it back over HTTPS the way a builders' tool does;
- if your builders need haks the module doesn't list, a second version for them, at `/builders` on the same
  address, sharing its files with the players' one.

Your git repository keeps the ASCII models. Only what goes into the haks is compiled.

### What Layonara does

- **Every ASCII model is compiled in the build,** with cleanmodels, in the builder image. Our last build had over
  a hundred thousand models, every one of them from the cache.
- **A broken model stops the build.** Nothing is packed and nothing is staged until it's fixed.
- **The build first proves it can see the game's own models,** with a tiny model whose supermodel only the game
  has. Without that, models that lean on the game's would compile quietly wrong.
- **Every version is written with its origins file.** Our builders use a build of Moonglow, a community toolset,
  with NWSync reading added, which makes real hak files on their computer from what players download.

### The human playbook

You need this chapter's tier 2: content built on the control host in the builder image, staged and promoted. The
examples use `CONTROL` for the control host's public address, as before.

The changed files are in [`templates/haks`](../templates/haks) and [`templates/content`](../templates/content):

- [`build.sh`](../templates/haks/build.sh), with `MODELS=compile`, and three example models in
  [`examples/my_models`](../templates/haks/examples/my_models) to try it on;
- [`builder/Dockerfile`](../templates/content/builder/Dockerfile), now with cleanmodels, and
  [`builder/nwsync-origins`](../templates/content/builder/nwsync-origins), which reads an origins file;
- [`publish.sh`](../templates/content/publish.sh), [`prune.sh`](../templates/content/prune.sh),
  [`lib.sh`](../templates/content/lib.sh), [`content.env.example`](../templates/content/content.env.example) and
  the [`Caddyfile`](../templates/content/Caddyfile), for the builders' version.

#### 27. GENERIC. Know what changes

- **Models are compiled between your checkout and the hak.** `build.sh` checks every ASCII model, compiles each
  one into a scratch copy of its hak, and packs that copy. Your checkout is never written to. Binary models, your
  own walkmeshes and every other file are packed as they are.
- **The compiler needs the game's data.** Many models lean on one of the game's: a creature on its skeleton, a
  tile on the game's materials. cleanmodels reads those from the game's own files, so the control host needs a
  copy of them.
- **Players download nothing new.** The origins file is a small text file beside each version. Tier 2's
  `publish.sh` already writes it; this tier adds the script that reads it, and the builders' version.

#### 28. ADAPT. The game's data on the control host

Change: where your game is installed.

From your own computer, copy the `data` folder of your own game install, about 4.5 GB, to the control host:

```sh
rsync -a --info=progress2 "$HOME/.local/share/Steam/steamapps/common/Neverwinter Nights/data/" nwn@CONTROL:nwn-data/data/
ssh nwn@CONTROL ls nwn-data/data/nwn_base.key
```

On Windows or a Mac, the folder is under your Steam or GOG library instead; it's the one holding `nwn_base.key`.

It has to be a game install. The game server's own data, as in the NWNX image, leaves out the models a server
doesn't need, so models that lean on them would compile wrong. The build checks this for you in the next step.
This folder is only read by the build, and it isn't in the download folder, so nobody downloads it.

#### 29. GENERIC. The new builder image

From your own computer, the new scripts and the image's files:

```sh
scp -r templates/content/* nwn@CONTROL:content/
```

`content.env` isn't in the templates, so yours stays as it is. On the control host, build the new image, and tell
the scripts to use it and to compile:

```sh
docker build -t nwsync-builder:2.3.2-cm4.18.3 ~/content/builder
cat >> ~/content/content.env <<'END'
IMAGE=nwsync-builder:2.3.2-cm4.18.3
MODELS=compile
END
```

The image took 45 seconds to build on the test, 312 MB. Like the neverwinter.nim tools, cleanmodels is downloaded
at one version and checked against a checksum written in the `Dockerfile`, and the image refuses to build if
cleanmodels says it's another version. A new version of cleanmodels is the same three moves as step 25: its two
lines in the `Dockerfile`, the tag in `content.env`, then stage as usual.

#### 30. GENERIC. Switch it on in the content repository

Copy the new [`build.sh`](../templates/haks/build.sh) into your content repository, over the old one, and merge
it. To see it work before your own models go through it, copy the examples in too:

```sh
cp ~/guide/templates/haks/build.sh ~/myhaks/
cp -r ~/guide/templates/haks/examples ~/myhaks/
cp -r ~/myhaks/examples/my_models ~/myhaks/haks/      # a new hak, to try; take it out again after
```

(Here `~/guide` is your copy of this guide.) Commit, push, and stage as in step 21. The first lines of
`publish.sh` now say what happened to the models:

```text
3 ASCII models
checked 0 unchanged models by their checksum, 3 with cleanmodels
compiled 3 models, 0 of them from the cache
packed build/hak/my_models.hak (3 files)
```

Stage again, and the same lines say the work was saved:

```text
checked 3 unchanged models by their checksum, 0 with cleanmodels
compiled 3 models, 3 of them from the cache
```

The cache is in `~/model-cache` on the control host. A compiled model is used again only while the model, the
version of cleanmodels and everything the compile looked up (supermodels, skeletons, materials) are unchanged,
so a changed supermodel compiles its children again by itself. Anything no build has used for two weeks is
removed at the end of a build. You can delete the whole folder whenever you like; the next build is just slower.

If the build says *"the game's data is not in reach"*, step 28 isn't done, or the folder isn't a game install.

#### 31. GENERIC. When a model is refused

A model that fails its check stops the build before anything is packed, and nothing is staged. On the test, with
two broken models pushed:

```text
5 ASCII models
these models fail their check; nothing was packed:
haks/my_models/ex_bad.mdl: node "m" references missing parent "nowhere"; would be reparented to "ex_bad"
haks/my_models/ex_broken.mdl: line 30: node "crate", verts: entry has 2 value(s), expected 3; the missing ones are set to 0
```

What players get doesn't change. Whatever was staged before isn't staged any more, as with any run of
`publish.sh`, so `promote.sh` refuses until a build works. Fix the model in your modelling tool (or run `cleanmodels check` on it at home to see
everything it finds), push, and stage again.

The rule is strict on purpose. A model that the game would load with a node in the wrong place, or with made-up
vertices, is a bug report from a player some weeks later. Warnings, such as a mesh with no texture, don't stop
the build.

#### 32. GENERIC. The same build at home

To try models before you push, the same `build.sh` compiles at home. You need
[cleanmodels](https://github.com/plenarius/cleanmodels/releases), `jq` and `perl` on your PATH, and the game:

```sh
MODELS=compile NWN_ROOT="$HOME/.local/share/Steam/steamapps/common/Neverwinter Nights" ./build.sh
```

At home the cache is `build/model-cache`, which git ignores. Without `MODELS=compile`, `build.sh` packs your
models as they are, as before.

#### 33. GENERIC. Read the origins file

Each version you publish has a file beside its manifest, `manifests/<version>.origin`. A manifest only lists
files by name and checksum; the origins file says which hak or talk table each one comes from, and where two haks
hold the same file, only the one that wins in the game lists it. With it, a builders' tool can rebuild your real
hak files from what players download, without you handing haks around.

The builder image has a script that reads it the way such a tool does. It downloads the manifest and the origins
file over HTTPS, checks that the two agree, file for file, and prints what came from where:

```sh
docker run --rm nwsync-builder:2.3.2-cm4.18.3 nwsync-origins https://nwsync.example.org
```

```text
version 77b61e9cea39a7d4f82e759be14976ee7c32d093: 5 files from 3 haks and talk tables
  my_first_hak.hak     1 files
  my_models.hak        3 files
  my_tlk.tlk           1 files
```

Give it a version and file names, and it says which hak each comes from; that's the question a builder asks when
a texture looks wrong:

```sh
docker run --rm nwsync-builder:2.3.2-cm4.18.3 nwsync-origins https://nwsync.example.org latest ex_crate.mdl ex_notes.2da
```

[Moonglow](https://github.com/jadzziaa/moonglow-toolset), a community toolset for NWN, has NWSync reading
offered as a change (its pull request 53, open as I write, 2026-11-26). With it, its `mg nwsync-pull` and
`mg nwsync-haks` download a version and write the haks from it. On the test they rebuilt every hak and the talk
table from the download, byte for byte the same as the build's.

#### 34. ADAPT. A version for builders, if you need one

Change: only if your builders need haks the module doesn't list.

Players only download the haks the module lists. Sometimes builders need more: a hak of new content that's not in
the module yet, or a kit of pieces only builders place. With `BUILDERS=yes`, `publish.sh` also writes a second
version with every hak the build made, at `/builders` on the same address. Its files sit beside the players' ones
and are stored once, so a file in both costs nothing twice.

On the control host:

```sh
echo BUILDERS=yes >> ~/content/content.env
```

The new `Caddyfile` from step 29 keeps the builders' `latest` from being cached. Caddy reads it only when it
starts, so restart the downloads service once in Coolify. Then stage as usual; one more line appears:

```text
builders get c0fb1843a53c26ec684e72601f82352626279d88 (6 files) at https://nwsync.example.org/builders
```

The builders' version moves when you stage, not when you promote: builders work on what comes next, players get
it when you promote. It is checked over HTTPS like the players' one, and the tidy-up keeps whatever the
builders' `latest` names. Point a builders' tool at `https://nwsync.example.org/builders`; for Moonglow, that's
`source` under `[nwsync]` in the project's `moonglow.toml`. The game itself never sees this address.

#### 35. LAYONARA-ONLY. A hundred thousand models

Our build compiles over a hundred thousand models. The steps are the same; our cache is just much bigger, and an
ordinary build takes every model from it.

### The agent playbook

If you work with an AI agent, [`playbooks/07-haks-nwsync-tier3.md`](../playbooks/07-haks-nwsync-tier3.md) has
these steps in a fixed shape it can follow. It asks before it copies the game's data, before it switches on the
builders' version, and whenever a model is refused (the fix is a modeller's, not the agent's).

### Lessons

- **The server's game data isn't enough to compile models.** The dedicated server leaves out models it doesn't
  need. With only that, cleanmodels compiled my test model with a single warning about a missing supermodel, and
  the result would have loaded wrong. That's why `build.sh` compiles a tiny model against the game's own
  `a_ba` first and stops if there's any warning.
- **Not every problem fails the checker.** A model with a short list of vertices is read with the missing values
  set to 0, and cleanmodels says so as a warning, not an error. On my first try a model like that went through.
  `build.sh` now reads cleanmodels' report and refuses those too.
- **Remember a check with its rules.** `build.sh` remembers which models passed, by checksum, to save time. When
  I made the rules stricter, the broken model from the last lesson was still remembered as good. The memory is now
  kept per version of cleanmodels and of `build.sh`, so a change to either checks everything again once.
- **Never write through a hard link.** The scratch copy of a hak is made of hard links to your checkout, which is
  quick and takes no space. Writing a compiled model into one of those links would change the file in your
  checkout too, so each link is removed first and the compiled file put in its place.
- **Use your own walkmeshes.** cleanmodels also writes a walkmesh for a tile it compiles. The build packs the one
  in your repository instead, the one your tile was made and tested with.

### Tested

On 2026-11-26, with Coolify 4.7.5, neverwinter.nim 2.3.2 and cleanmodels 4.18.3 in the image on `ubuntu:24.04`,
Docker 29.10 on Ubuntu 26.04, Caddy 2.11, on a pair of fresh Hetzner cloud servers of the smallest shared type,
brought to the state tier 2 leaves them in: the downloads service on the control host under a temporary name in
our own domain, with a real certificate, and the game advertising from it. A plain git repository on the control
host stood in for the content repository, and the game's data was copied from a Steam install of NWN:EE.

- the image: built in 45 seconds, 312 MB; cleanmodels' version checked;
- the canary: with the game's data, the build went on; with the game server's data from the NWNX image, it
  stopped with the missing supermodel;
- a stage with the three example models in two haks: all three checked and compiled, the packed models binary,
  the checkout unchanged; the next stage took all three from the cache;
- two broken models pushed (a node whose parent doesn't exist, and a short list of vertices): the build stopped
  with both named, nothing packed, nothing staged, players' `latest` unchanged; fixed and staged again; and a
  file that isn't a model at all, in a copy of the repository, refused the same way;
- the origins files from outside over HTTPS with `nwsync-origins`, for the players' and the builders' versions:
  every file found once, files mapped to the right haks, a missing file reported with an error;
- the builders' version: written with the one hak the module doesn't list, checked over HTTPS, its `latest` not
  cached; the tidy-up, with `KEEP=1`, removing two old versions and keeping the builders' one although it wasn't
  the newest, and it still downloading completely;
- Moonglow's command-line tool `mg`, a build with the NWSync change from its pull request 53: `nwsync-pull` and
  `nwsync-haks --all` from the builders' address, every hak and the talk table the same, resource for resource,
  as the build's.

Not tested: Moonglow's window itself (only its command-line tool, on a server with no screen), a content
repository the size of ours, and the first build after a new cleanmodels version with many models.
