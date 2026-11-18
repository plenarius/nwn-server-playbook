# Chapter 11. A website

**Status:** tier 1 is written and tested. Tier 2 (a page that shows who is online, character pages) and tier 3 (one
sign-in shared by a website, a forum and a wiki) are not written yet.

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
two small files in `templates/game`: [`sites/www.caddy`](../templates/game/sites/www.caddy) and
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
scp templates/game/sites/www.caddy templates/game/.env.site.example nwn@SERVER:game/
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
