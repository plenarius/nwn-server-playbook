# Chapter 7. Custom content: haks, the talk table and NWSync

**Status:** tiers 1 and 2 are written and tested. Tier 2, further down, builds and serves the content from the
control host and cleans out old content. Staging, and tier 3 (compiled models, content for builders' tools), are
not written yet.

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
nwn_nwsync_write --description="My server's content" --path build/hak --path build/tlk build/nwsync ~/mymodule/mymodule.mod
```

This reads the module, finds the haks and the talk table it lists, and writes them into `build/nwsync` in the form
players' games download. The folder must exist first, which is what the `mkdir` is for.

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
1's tier 2. The game host then only runs the game. One script on the control host builds from your repository,
publishes the new version for players' games, sends the files to the game host, and tidies away old versions,
carefully.

When you're done, you'll have:

- your content repository cloned on the control host, which builds it;
- the download address served by Coolify on the control host, with its own certificate;
- [`templates/content/publish.sh`](../templates/content/publish.sh): one command from a merged change to files
  waiting on the game host for chapter 16's `release.sh`;
- old versions removed only when nothing can still need them, the one the live game hands out above all;
- a game host with no web server and nothing open but the game.

Players notice none of it until you release, and the release itself is the same few seconds as before: 8 on the
test.

### What Layonara does

- **A merge builds everything on our build machine,** never on the game host: 57 haks and the download folder, in
  about 21 minutes.
- **The download folder is served by a Coolify service** with its own name and certificate.
- **The game host receives finished files** and swaps them in when we release.
- **The tidy-up keeps what the live game hands out.** It reads the version from the game itself before it removes
  anything.

### The human playbook

You need chapter 1's and chapter 3's tier 2, and chapter 4's tier 2 is a good idea first, so that Coolify already
runs the game. The examples use `GAME` for the game host's public address and `CONTROL` for the control host's. The
game host's private address is `10.77.0.2`, as in chapter 1.

The new files are in [`templates/content`](../templates/content): `publish.sh`, and
[`downloads.yaml`](../templates/content/downloads.yaml) with its [`Caddyfile`](../templates/content/Caddyfile), the
downloads service.

#### 13. GENERIC. Know what moves

- **The build** moves to the control host. It clones your content repository and builds from it, exactly as
  `build.sh` does on your own computer.
- **The download folder** moves to the control host, and the name players download from moves with it. The game
  doesn't need to know: it asks the same name as before.
- **The game host keeps its haks and talk table.** The game needs them on its own disk. `publish.sh` sends them
  across the private network, and you release them as before.

#### 14. GENERIC. Tools, a key and the repository on the control host

On the control host, as `nwn`. The tools come as a zip file, and a fresh Ubuntu has no `unzip`:

```sh
sudo apt-get install -y unzip
mkdir -p ~/nwn-tools && cd ~/nwn-tools
curl -fsSL -o nw.zip https://github.com/niv/neverwinter.nim/releases/download/2.3.2/neverwinter-x86_64-linux-gnu.zip
unzip -oq nw.zip && rm nw.zip
ssh-keygen -t ed25519 -N "" -C "nwn@control" -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub
```

That last key is the control host's own. It does two jobs:

- **On GitHub,** in your content repository: **Settings**, **Deploy keys**, add it, **read-only**. The control host
  can then read the repository, and nothing else on GitHub.
- **On the game host,** add the same line to `~/.ssh/authorized_keys`, so the control host can send it files:

  ```sh
  ssh nwn@GAME 'cat >> ~/.ssh/authorized_keys'   # paste the line, then Ctrl-D
  ```

Then, back on the control host, check both and clone:

```sh
ssh nwn@10.77.0.2 hostname        # answer "yes" to the first-time question
ssh-keyscan github.com >> ~/.ssh/known_hosts
git clone git@github.com:you/myhaks.git ~/myhaks
cd ~/myhaks && PATH=~/nwn-tools:$PATH ./build.sh
```

The build should pack your haks and the talk table, as it does at home.

#### 15. GENERIC. Copy the download folder across

The control host starts with everything the game host serves today, so no player's download breaks when the name
moves:

```sh
mkdir -p ~/nwsync ~/content
rsync -a nwn@10.77.0.2:game/nwsync/ ~/nwsync/
cat ~/nwsync/latest
```

And from your own computer, the downloads service's settings file and the script:

```sh
scp templates/content/Caddyfile templates/content/publish.sh nwn@CONTROL:content/
```

The `Caddyfile` has to be there before the service starts. Otherwise Docker makes an empty folder in its place, and
the service won't start.

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

#### 20. GENERIC. Publishing, from now on

When a change to your content is merged, on the control host:

```sh
~/content/publish.sh ~/mymodule.mod
```

The module file is the one you're about to release: fetch it as in chapter 16's step 6 and copy it to the control
host. Its list of haks decides what goes into the new version, and it travels to the game host with the content.
The script then:

1. pulls the repository's newest commit and builds;
2. writes the new version into `~/nwsync`. The running game keeps handing out the old version, which is still
   there;
3. sends the haks, the talk table and the module to `~/incoming` on the game host;
4. tidies away old versions, then tells you what it kept.

Then on the game host, `sudo ./release.sh` as in chapter 16 swaps them in, and the game advertises the new version
when it comes back. Together, the two take the place of chapter 16's step 5 and the content half of its step 6.

The tidy-up removes an old version only when all four of these hold: it isn't among the newest three, it isn't what
`latest` names, it isn't what the game says it is handing out right now, and it's more than 7 days old. Content
files no remaining version uses go too, once they're 7 days old. If the script can't ask the game which version it
hands out, it removes nothing and says so. Only one publish runs at a time.

The settings at the top of the script (`CONTENT_DIR`, `KEEP` and the rest) can be set in front of the command, for
example `KEEP=5 ~/content/publish.sh ~/mymodule.mod`.

#### 21. LAYONARA-ONLY. Seventeen gigabytes, again

Our build runs on its own machine and takes about 21 minutes, because of the size of our content. The steps above
are the same; ours just take longer, and our build machine has a disk sized for two copies of everything.

### The agent playbook

If you work with an AI agent, [`playbooks/07-haks-nwsync-tier2.md`](../playbooks/07-haks-nwsync-tier2.md) has these
steps in a fixed shape it can follow. It asks before it moves the name, and before it restarts the game.

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
- `publish.sh` with no change and with a merged change; the files sent; `release.sh` in 8 seconds; the game
  advertising the new version;
- the tidy-up, with every file aged to 10 days: three more publishes removed the two oldest versions one at a time,
  kept the version the game was handing out although it was older than the newest three, removed the content files
  only the removed versions used, and the kept version still downloadable;
- a reboot of the control host: the downloads back by themselves within about two minutes;
- on an earlier pair, the deploy-first order: the first certificate request failed, and the game, restarted then,
  stopped and was restarted by Docker 29 times until the address worked again.

Not tested: the downloads service's dashboard forms by hand (the service was made through Coolify's API), a publish
while another runs, and a content repository the size of ours.
