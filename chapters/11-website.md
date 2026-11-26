# Chapter 11. A website

**Status:** tier 1 is written and tested. Tier 2, further down, is written and tested in two parts: the site moves
to the control host with deploy on merge, then gains a live status page. Pages for characters come with tier 3,
together with one sign-in shared by a website, a forum and a wiki; those are not written yet.

## What you learn

How to give your world a front door: one page, at your own name, with a real certificate, that says what this place
is and how to get in.

When you're done, you'll have:

- a single HTML file, yours to rewrite, kept in git like everything else;
- that page served at `https://www.example.org` by the same small web server as chapter 7;
- one command that publishes a change.

It's a deliberately small chapter. A page that tells a curious visitor how to join in under a minute does more for
a new world than a grand site that is never finished.

**Time:** about fifteen minutes, most of it spent on your own words. On the test, the page was live with its
certificate a few seconds after the web server started.

## What Layonara does

- **A full website,** on a different machine from the game, with pages that show who is online, characters, the
  world's lore and a good deal more. It grew over many years and is far past tier 1.
- **It holds no keys to the game.** The website can't reach the game's database. Everything it shows about the game
  it asks for from a small service in between. That separation is the main idea of this chapter's later tiers.
- **One sign-in** covers the website, the forum and the wiki.
- **The community itself lives on Discord.** The website tells people what the world is and how to join. The
  talking happens where people already are.
- **We never publish a password** on a page. Anyone who needs one asks a person.

The last two are the parts of our setup that fit a brand-new world as they are, and the template page is built
around them.

## The human playbook

Each step carries a label: GENERIC (the same for any server), ADAPT (works once you change the things it names) or
LAYONARA-ONLY (something we do that you probably shouldn't copy).

The files for this chapter are [`templates/site/index.html`](../templates/site/index.html), the page itself, and
two small files in `templates/game`: [`sites-available/www.caddy`](../templates/game/sites-available/www.caddy) and
[`.env.site.example`](../templates/game/.env.site.example).

### 1. ADAPT. Make the page yours

Change: every word on it.

```sh
cp -r templates/site ~/mysite
cd ~/mysite
git init -b main
```

Open `index.html` in a text editor. The comment at the top lists the five things to change: the name, the line
under it, the address in "How to join", the paragraph about your world, and the link to where your community talks.
Open the same file in your web browser to see it as you go. It is one file with no scripts and nothing loaded from
anywhere else, so what you see on your own computer is exactly what visitors will get.

Two things I'd ask you to keep:

- **The steps for joining.** They're the reason most visitors came.
- **No password on the page.** If your server needs one to join, say where to ask. A password on a web page is read
  by everyone, including the people it was meant to keep out.

Commit it when you like it: `git add -A && git commit -m "My site"`.

### 2. GENERIC. Give the site a name

Add a DNS record, `www`, that points at your machine (chapter 2). As always, create it first and look it up
afterwards.

### 3. GENERIC. Make sure the web server is there

**If you did chapter 7,** it already is. Go on to step 4.

**If you skipped chapter 7,** three things from it are needed here. Open the web ports at your provider's firewall
(TCP 80 and 443) and on the server, copy the web server's two files, and tell Docker to use them:

```sh
ssh nwn@SERVER 'cd ~/host && sudo ALLOW_WEB=1 STEPS=firewall ./prepare-host.sh'
scp templates/game/compose.web.yaml templates/game/Caddyfile nwn@SERVER:game/
ssh nwn@SERVER
cd game
nano .env       # add ":compose.web.yaml" to the end of the COMPOSE_FILE line
```

If your `.env` has no `COMPOSE_FILE` line at all, because you skipped the database chapter too, add the line
`COMPOSE_FILE=compose.yaml:compose.web.yaml`.

### 4. GENERIC. Send the page and switch the site on

From your own computer:

```sh
ssh nwn@SERVER 'mkdir -p game/sites game/site && sudo chown nwn: game/site'
rsync -a --delete --exclude .git ~/mysite/ nwn@SERVER:game/site/
scp templates/game/sites-available/www.caddy templates/game/.env.site.example nwn@SERVER:game/
```

Then, on the server:

```sh
cd ~/game
mv www.caddy sites/
cat .env.site.example >> .env
nano .env                        # put your own name in the SITE_HOST line
docker compose up -d caddy
```

The last command starts or refreshes only the web server. Your game keeps running, and nobody playing notices.

### 5. GENERIC. Check it

Open `https://www.example.org` in your browser. You should see your page, with the padlock.

From a terminal, the same check without a browser:

```sh
curl -sI https://www.example.org | head -1
curl -s https://www.example.org | grep '<title>'
```

The first line should end in `200`, and the second should show your own title. Give the certificate a few seconds
on the very first start.

If the page doesn't come up, `docker compose logs caddy` on the server says why. One message is worth knowing in
advance: `unrecognized global option` means there is a file in `sites/` whose name isn't set in `.env`. Each site
file needs its name: `www.caddy` needs `SITE_HOST`, and `nwsync.caddy` from chapter 7 needs `NWSYNC_HOST`.

### 6. GENERIC. Changing the page later

Edit, look at it in your browser, commit, and send it:

```sh
rsync -a --delete --exclude .git ~/mysite/ nwn@SERVER:game/site/
```

That's all. The web server serves files straight from that folder, so a change is live the moment it arrives, and
nothing needs restarting. `--delete` keeps the server's folder identical to yours, so a file you remove at home
disappears there too.

Pictures and more pages work the same way: put them in `~/mysite`, link to them from your page, send. For a small
site, that's all there is to it.

### 7. LAYONARA-ONLY. Forum, wiki and a shared sign-in

We run a forum and a wiki beside the website, with one account for all three. They hold twenty years of a
community's writing, and they're there because that history is worth keeping. A new world doesn't need them to
begin with. A page and a place to talk carry a community a long way.

## The agent playbook

If you work with an AI agent, [`playbooks/11-website.md`](../playbooks/11-website.md) has these same steps in a
fixed shape it can follow. The words on the page are yours: an agent publishes what you wrote, and it stops and
asks before it writes or changes what your world says about itself.

## Lessons

These are the things we've learned about a world's front door, written down so you can skip the learning.

- **The page's job is to get someone in.** People arrive with one question: how do I join? The template answers
  that before anything else.
- **Put the community where people already are.** Our conversations moved to Discord over the years, and the forum
  became the archive. If you're starting today, start where your players already spend their evenings, and let the
  page point there.
- **Never a password on a page.** We don't publish ours anywhere. Whoever needs it asks a person.
- **Keep the website away from the game's data.** Our website has no way into the game's database at all. A
  one-page site can't get this wrong, since it talks to nothing. It's worth remembering on the day yours grows.

## Tested

On 2026-11-18, with Caddy 2.11, on a fresh Hetzner cloud server of the smallest shared type that had been through
chapters 1, 4, 5, 6 and 7, and two temporary names in our own domain:

- the page sent with `rsync`, without its `.git` folder;
- the site switched on beside the download address from chapter 7, each with its own certificate, with the game's
  container left untouched;
- the page from outside: found, with the right title, compressed, plain HTTP sent on to HTTPS, and a missing page
  answered as missing;
- the download address still working afterwards;
- the web server's setup with a website only, and the error when a site file's name isn't set;
- the path for readers who skipped chapter 7, on a clean folder: the web server started for the first time with the
  website as its only site.

I also looked at the template page in a browser, in a desktop window and at a phone's width in dark mode.

Not tested: a site with more than one page, and a `www` name together with the bare domain.

---

## Tier 2. The website on the control host, deployed on merge

### What you learn

How to move your website off the game host and onto the control host from chapter 1's tier 2, where Coolify builds
it from GitHub and puts every merged change live by itself.

When you're done, you'll have:

- your site in its own private repository on GitHub, with a two-line `Dockerfile`;
- the site running as a Coolify application on the control host, with its own certificate;
- a merged pull request live within half a minute, without anyone logging in anywhere;
- a game host with one job less.

Nobody visiting notices the move. On the test the site was away for a few seconds at most, while the name moved.

### What Layonara does

- **Our website is a Coolify application,** on a machine of its own, built from GitHub on every merge.
- **It deploys through a plain repository webhook,** the same kind chapter 3 sets up.
- **Changes go through pull requests,** so someone looks at each one before it's live.

### The human playbook

You need chapter 3, and its step 10 done once, so the deploy-on-merge loop is familiar. The examples use `GAME` and
`CONTROL` for the two machines' public addresses, and `www.example.org` for your site.

#### 8. GENERIC. Know what changes

**The page itself doesn't change.** Only where it lives, and how a change gets there. In tier 1 you sent the folder
with `rsync`. From now on a merge on GitHub is the whole of it.

The site is built into a small container: the official `nginx` image with your files copied in. That's what the
[`Dockerfile`](../templates/site/Dockerfile) says, in two lines.

#### 9. GENERIC. Put the site on GitHub

Make a new **private** repository on GitHub for it, such as `you/mysite`. Then, at home:

```sh
cd ~/mysite
cp ~/nwn-server-playbook/templates/site/Dockerfile .
git add Dockerfile && git commit -m "Build the site into a container"
git remote add origin git@github.com:you/mysite.git
git push -u origin main
```

If your site has more files than `index.html`, add a `COPY` line for each to the `Dockerfile`, as its comment
shows. Pictures in a folder `images` take one line: `COPY images /usr/share/nginx/html/images`.

#### 10. GENERIC. The application, not deployed yet

As in chapter 3's step 10, with two differences:

1. A deploy key for this repository, read-only, made and added the same way.
2. In Coolify: **Projects**, your `web` project from chapter 7 (or a new one), add a resource, **Private Git
   Repository (with Deploy Key)**. The control host as its server, the key, the repository's SSH address, branch
   `main`, build pack **Dockerfile**, base directory `/` (or the folder that holds the `Dockerfile`).
3. **The difference:** no port mapping. Instead, set **Domains** to your site's name with `https://` in front,
   `https://www.example.org`. Coolify's proxy then serves it, and gets its certificate.

**Don't deploy yet.** And open TCP 80 and 443 at the control host's provider firewall, if chapter 7's tier 2 hasn't
already.

#### 11. GENERIC. Move the name, then deploy

The same order as chapter 7's step 17, for the same reason: the proxy asks for the certificate as soon as the site
starts.

1. Point `www.example.org` at the control host, as in chapter 2, and give it a few minutes.
2. **Deploy** the application.
3. Open `https://www.example.org`. You should see your page, with the padlock.

If you deployed first, the first certificate request fails. Once the name points at the control host, `docker
restart coolify-proxy` on it makes the proxy try again. That's what happened on the test, and the restart fixed it.

#### 12. GENERIC. The webhook

As in chapter 3's step 10: in the application, **Webhooks**, **Manual Git webhooks**, **GitHub**, **Generate** a
secret, save, and add the webhook on GitHub with that URL, `application/json`, the secret and just the push event.

Then try the whole loop once: change a word in a pull request and merge it. Within half a minute it's on your site.
On the test, it took 24 seconds.

#### 13. GENERIC. Switch off the old site on the game host

On the game host:

```sh
cd ~/game
rm sites/www.caddy
```

Then take `SITE_HOST` out of `.env`. If `sites` still holds `nwsync.caddy` (the downloads haven't moved yet), run
`docker compose up -d caddy` to apply it. If `sites` is now empty, the game host serves nothing on the web any
more: switch its web server off as in chapter 7's step 19, Coolify's proxy included. You can keep `~/game/site` as
a copy, or delete it.

#### 14. GENERIC. Changing the page, from now on

Edit at home, look at it in your browser, push a branch, open a pull request, merge. That's all. Coolify builds and
swaps the container in, and a visitor in the middle of loading the page gets either the old one or the new one,
whole.

### The agent playbook

If you work with an AI agent, [`playbooks/11-website-tier2.md`](../playbooks/11-website-tier2.md) has these steps
in a fixed shape it can follow. It asks before it moves the name, before it adds anything to your GitHub
repository, and before it touches the game host.

### Lessons

- **Move the name before you deploy.** Our test site deployed first, and its first certificate request failed. A
  proxy restart fixed it, but the order of step 11 avoids it altogether.
- **Certificates are rationed.** At most five for the same name in a week, from Let's Encrypt. Moving a name costs
  one, so practise on a spare name, not your real one.
- **Merge, don't upload.** A merged pull request is the only way a change reaches our website. Every change is
  reviewed, recorded, and easy to undo.

### Tested

On 2026-11-18, with Coolify 4.7.5, on a pair of fresh Hetzner cloud servers of the smallest shared type, the game
host serving the tier 1 site, with a throwaway private repository and a temporary name in our own domain:

- a deploy key and the application on the control host, built from the template `Dockerfile`, with its domain;
- the deploy-first order: the first certificate request failed, `docker restart coolify-proxy` after the name moved
  fixed it, and the page came up with a Let's Encrypt certificate;
- the webhook, and a merged change live on the public site 24 seconds after the merge;
- on a second pair, the agent playbook as written: the deploy key, the application made without deploying, the name
  pointed at the control host before the deploy, the webhook's ping and a push both answered `200`, and a merged
  change served 26 seconds after the merge.

On that second run, Let's Encrypt refused the certificate: the name had used up its five for the week in the
earlier tests. So the order of step 11 is tested for the downloads in chapter 7's tier 2, where it got its
certificate at once, but not for the website. The page itself was checked on the control host past the missing
certificate.

The application was made through Coolify's API, which does what those dashboard pages do.

Not tested: the dashboard forms by hand, a site with more than one file, and step 13 (no tier 1 site was left on
the second pair's game host).

---

## Tier 2, second part. A live status page

### What you learn

How to show visitors whether the game is up, how many people are playing, which module runs and since when, read
live from the operations API of chapter 9, without your website holding a single key a visitor could find.

When you're done, you'll have:

- a status page, `status.html`, in the same plain style as your front page;
- a small piece inside the site's own web server that asks the API on the visitor's behalf, and passes on only the
  four things the page shows;
- the API asked at most twice a minute, however many people have the page open;
- a page that stays calm when something is down: the game stopped says "Offline", and the API away shows the last
  thing it knew, with its time, or says it can't tell.

This part assumes chapter 9's setup: the operations API ([nwn-ops-api](https://github.com/plenarius/nwn-ops-api))
running in Coolify on the control host, listening only on the control host's private address, `10.77.0.1:8100`, with
a team key made for your staff's tools. The website from the first part runs on that same control host, so the two
talk without leaving the machine.

### What Layonara does

- **The website holds no keys to the game,** as in tier 1. It asks the operations API for everything it shows, over
  the private network, with keys that stay on the server.
- **Short caches everywhere.** Who is online is cached for 15 to 30 seconds, a character for five minutes, so a busy
  evening on the website is a quiet one for the API.
- **Pages still render when the API is away.** Each section that depends on it says it can't reach the server, and
  the rest of the page works.
- **Character pages, portraits and more** come from game-data services in our API that go well past chapter 9's
  operations core: a character index, a picture renderer and their own database. nwn-ops-api has none of those
  yet, so character pages are a tier 3 part of this chapter.

### The human playbook

You need the first part of this tier done, and chapter 9's API answering. Your site's repository already has
`index.html` and the two-line `Dockerfile`.

#### 15. GENERIC. Know where the key stays

The API wants a key with every question, and a key in a web page is a key for everyone. So the browser never
talks to the API. It asks your own site for `/status.json`, and the site's web server asks the API:

```
visitor's browser  --  /status.json  -->  your site (nginx, on the control host)
                                              |  team key, over the private address
                                              v
                                          operations API  --  SSH  -->  game host
```

The files that do it are in [`templates/site/status`](../templates/site/status):

- [`status.html`](../templates/site/status/status.html), the page, with a few lines of script that ask
  `/status.json` once a minute;
- [`status.js`](../templates/site/status/status.js), run by nginx itself on the server: it asks the API, and keeps
  only the state, the number of players, the module and the start time;
- [`nginx.conf`](../templates/site/status/nginx.conf), which serves your pages as before, keeps the API's answer
  for 30 seconds, and falls back to the last good answer when the API doesn't reply;
- a new [`Dockerfile`](../templates/site/status/Dockerfile) that puts all of that together.

The API's full answer says more than the page shows: which modules are staged, which NWNX build is waiting, what
changes are pending. That's your team's business, so `status.js` passes on only what the page needs. A field
added to the API later stays private too, until you choose to show it.

One thing to know about the key. In nwn-ops-api today, the smallest key is the team key, and it can also restart
the game. It never leaves the control host: it lives in Coolify, and in the environment of the one container that
uses it, which only ever asks two questions. Anyone who can reach it there could already do much more, since they'd
be on your control host.

#### 16. ADAPT. Add the files to your site

Change: the names in `status.html`.

```sh
cd ~/mysite
git switch -c status-page
cp ~/nwn-server-playbook/templates/site/status/* .
```

That replaces your `Dockerfile` with the new one. If you had added `COPY` lines to the old one for pictures or more
pages, add them again to the new one.

Open `status.html` in a text editor and put your world's name in `<title>` and `<h1>`, and your colour in the first
line of the `<style>` block, the same one as on your front page. Then add a link to it on your front page,
wherever you like; under "How to join" is a good spot:

```html
<p><a href="/status.html">Is the server up?</a></p>
```

If you'd like to see it before it goes anywhere, and you have Docker at home:

```sh
docker build -t mysite . && docker run --rm -p 8080:80 mysite
```

and open `http://localhost:8080/status.html`. It says "Can't tell right now", which is right: it has no key and no
API at home. That's also exactly what a visitor sees on the day the API is down, so it's worth a look.

#### 17. GENERIC. Give the site the address and the key, in Coolify

In Coolify, open the website application, **Environment Variables**, and add two:

| Name | Value |
|---|---|
| `OPS_API_URL` | `http://10.77.0.1:8100`, the API's private address from chapter 9 |
| `OPS_API_TEAM_KEY` | the team key from chapter 9, from your password manager |

For both, **untick "Available at Buildtime"**, and leave "Available at Runtime" ticked. This one matters: Coolify
ticks build time by default, and then writes the value into the image as it builds it, where `docker history`
shows it to anyone on the control host for as long as the image exists. The site needs the key only while it runs.

If Coolify lists the two again under **Preview Deployments**, delete those copies. Previews of pull requests don't
need the key.

Nothing needs opening in a firewall: the site and the API are on the same machine, and the site reaches the API's
private address directly. On the test, it worked with the firewall exactly as chapter 1 left it.

#### 18. GENERIC. Merge, and look

Push the branch, open a pull request, merge it. Coolify builds and puts it live, as in step 14.

Open `https://www.example.org/status.html`. You should see "Online", with the number of players, the module and
when the game last started. From a terminal:

```sh
curl -sI https://www.example.org/status.json | grep -iE '^HTTP|cache-control|x-status-cache'
curl -s https://www.example.org/status.json
```

The first command shows `200`, `cache-control: public, max-age=30`, and `x-status-cache`: `MISS` the first time,
`HIT` straight after. The second shows the whole of what visitors get, something like:

```json
{"state":"online","players":0,"module":"mymodule","started":"2026-11-26T15:56:47.000Z","restart_at":null,"checked":"2026-11-26T16:06:54.663Z"}
```

`module` is the version when your module's name carries one (`world_2-05` shows as `2.05`; the API's
`MODULE_VERSION_REGEX` setting decides), and the name itself otherwise. `restart_at` is set during a restart countdown, once your module handles
chapter 9's restart command; the page then says when.

And the check I'd never skip: in your browser, **View source** on the status page, and search for the first few
characters of your key. They aren't there, and they shouldn't be anywhere a browser can reach.

#### 19. GENERIC. Know what visitors see when things go wrong

You don't have to do anything here; it's so nothing surprises you.

- **The game is stopped,** for a restart or a deploy: the page says "Offline" within about half a minute, and that
  it's usually back within a few minutes.
- **The API is down or not answering:** the site keeps the last good answer for a day, and the page shows it as
  "Last known", with the time it was true. Visitors get it at once, while the site keeps trying the API in the
  background, giving it ten seconds each time.
- **The API is down and the site has nothing kept,** say right after a deploy of the site: the page says "Can't
  tell right now", and that the game itself may be fine.

When the page doesn't look right, the site's log in Coolify says why, in lines that start with `status:`. For
example, `the operations API did not answer: connect failed` means the API isn't running, and `set OPS_API_URL and
OPS_API_TEAM_KEY` means step 17 is missing.

#### 20. GENERIC. Cloudflare needs nothing new

If your site is behind Cloudflare's proxy (chapter 2's tier 2), leave its cache settings alone. Cloudflare doesn't
keep JSON by default, so every visitor's question reaches your site, and your site's 30-second cache is what
protects the API. Please don't add a "cache everything" rule: pages that change by the minute are exactly what it
would get wrong.

### The agent playbook

If you work with an AI agent, [`playbooks/11-website-tier2-status.md`](../playbooks/11-website-tier2-status.md)
has these steps in a fixed shape it can follow. A person places the key in Coolify; the agent checks that it is
there, set for run time only, and that no page shows it. It asks before it opens a pull request on your site.

### Lessons

- **A key in a web page is a key for everyone.** The browser asks your site; your site asks the API. It's one more
  file, and it's the difference between a status page and an open door.
- **Show the public only what you mean to.** Pass on the fields the page needs, by name. An API grows, and a page
  that forwards everything forwards tomorrow's private fields too.
- **Untick "Available at Buildtime" for secrets in Coolify.** On the test, the key went into the image's history
  with Coolify's default, and out of it once the box was unticked.
- **Cache where you control it.** Cloudflare passes JSON straight through, so the site's own cache is the one that
  counts. On the test, 200 visits at once asked the API once.
- **A down service says so, kindly.** Cloudflare replaces a `502` from your server with its own error page, so the
  site answers `503` when the API is away, and the page turns that into words a visitor understands.

### Tested

On 2026-11-26, with Coolify 4.7.5, nginx 1.29.8 with its JavaScript module (njs 0.9.6), and nwn-ops-api at commit
`e77f32c`, on a pair of fresh Hetzner cloud servers of the smallest shared type in the state chapter 3 leaves them,
with the game running on the game host. The API's image was built on the control host from a checkout of
nwn-ops-api and run there on the private address with a team key, as chapter 9 sets it up, but with plain Docker
Compose rather than as a Coolify service. The website was a Coolify application built with the Dockerfile build
pack from the template files, and its repository was a git repository on the control host itself, reached with a
deploy key, instead of GitHub: the GitHub side is the first part's, unchanged. A temporary name in our own domain
pointed at the control host through Cloudflare's proxy.

- the page in a browser at desktop and phone widths: online, with the player count, the module and the start time;
- the game stopped: "Offline" on the next refresh; started again: "Online", with the new start time;
- the API stopped: the last good answer, marked "Last known" with its time; the API paused so it hung: the last
  good answer served at once, while nginx's log showed its background calls timing out after ten seconds;
- the site redeployed while the API was stopped, so nothing was kept: "Can't tell right now";
- 200 requests at once through Cloudflare: the API asked once (one status call, in its log);
- the cache headers: `public, max-age=30`, `x-status-cache` `MISS` then `HIT`, Cloudflare's `DYNAMIC`, and a query
  string that can't get past the cache;
- the key: absent from every page and file the site serves, absent from the image once "Available at Buildtime" was
  unticked (present in its history before), and present only in the running container's environment;
- the site with no settings at all (at home): `503` and the `status:` line in its log that names the two settings.

The application and its settings were made through Coolify's API, which does what the dashboard pages do.

Not tested: a player online (the count was 0 throughout), the restart countdown on the page (it needs chapter 9's
Redis part), the dashboard forms by hand, and the page in dark mode (it uses the front page's colours, which were
checked in dark mode in tier 1).
