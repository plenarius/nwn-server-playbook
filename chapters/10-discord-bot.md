# Chapter 10. The Discord bot

**Status:** tier 2 is written and tested. Tier 1 doesn't need a bot. Tier 3 (bug reports from Discord, a chat
bridge with the game, a roster of who's online) is not written yet.

A Discord bot is a program that logs in to Discord as its own user. It can post, edit its posts, show buttons and
answer slash commands, the commands you type after a `/`.

## Tier 1

Nothing to do here. With one machine and one person, `ssh` and chapter 4's status check are all you need. Come back
when you have a team that wants to see the server, and restart it, without a login to your machines.

## Tier 2. A dashboard, a restart button and a changelog

### What you learn

How to give your team one place in Discord to see the game, and a safe way to restart it that needs no access to
your machines. And how to turn every merged pull request into a short post your players can read.

When you're done, you'll have:

- a small bot of your own, about 550 lines of Python, in its own private repository;
- a **dashboard** message in one channel, edited every minute: online or not, players, module, last restart;
- **Restart** and **Cancel restart** buttons under it, and `/restart` and `/cancel-restart`, for one role only;
- a **changelog** channel where each merged pull request appears a few seconds after the merge;
- the bot running in Coolify on the control host, deployed on merge like your website.

The bot never touches the game host. Everything it does goes through the operations API from chapter 9, with the
API's **team key**, which can look and restart and nothing else.

**Time:** about an hour, most of it in Discord's and GitHub's settings pages.

### What Layonara does

- **Our bot is one Python program** with discord.py, as here, but much bigger: about twenty parts, from the
  dashboard to bug reports and a chat bridge with the game.
- **The dashboard is one message**, edited every 60 seconds from the operations API, with buttons for restart,
  deploys, NWNX updates, releases and the game's log. Who may press which button depends on their Discord role.
- **The changelog is a webhook.** GitHub calls the bot whenever something happens in our content repositories; the
  bot checks GitHub's signature, answers at once, and posts each merged change. Later, a release gathers them into
  one post.
- **It deploys from GitHub on every merge**, through Coolify.

This chapter's bot is written fresh for the guide: the dashboard, two buttons and the changelog, nothing of ours
you'd have to take out again.

### The human playbook

You need chapter 9 done: the operations API running on the control host at `http://10.77.0.1:8100`, with its team
key in your password manager. And chapter 11's tier 2 once, so a Coolify application deployed from GitHub is
familiar. The examples use `CONTROL` for the control host's public address and `bot.example.org` for the name GitHub
will call. The files are in [`templates/bot`](../templates/bot).

#### 1. GENERIC. Know what the bot is

One program, three jobs:

| Job | How it works |
|---|---|
| Dashboard | Every minute it asks the operations API for the game's status and edits one message in place |
| Restart and cancel | A button or a slash command; the bot checks the person has the staff role, then calls the API |
| Changelog | A small web server inside the bot. GitHub sends it each pull request event, signed with a secret you share; a merge becomes a post |

The bot keeps one thing on disk: the id of its dashboard message, so after a restart it edits the same message
instead of posting a new one.

**Why the team key, and not the admin key?** The team key opens status, restart and cancel, which is everything this
bot does. If the bot's settings ever leak, the most anyone can do with that key is restart your game. Deploys, stops
and releases stay with the admin key, in your own hands.

#### 2. GENERIC. Make the bot in Discord

1. Open the [Developer Portal](https://discord.com/developers/applications), **New Application**, and name it.
2. **Bot**: **Reset Token**, and put the token straight into your password manager. Anyone with it *is* your bot.
3. Still on **Bot**, leave all three **Privileged Gateway Intents** off. This bot reads no messages and needs none.
4. **OAuth2**, **URL Generator**: scopes `bot` and `applications.commands`; bot permissions **View Channels**,
   **Send Messages**, **Embed Links** and **Read Message History**. Open the URL it makes and add the bot to your
   Discord server.

#### 3. ADAPT. Two channels and a role

Change: the names, to suit your server.

- `#server-status` for the dashboard: everyone can read it, only the bot posts in it.
- `#changelog` for the changelog, the same way.
- A role for the people who may restart the game, such as `Staff`.

Then switch on **Developer Mode** in your Discord app (**Settings**, **Advanced**), and right-click to **Copy ID** for
your server, both channels and the role. You'll need all four numbers in step 5.

#### 4. GENERIC. Give the bot its own repository

Make a new **private** repository on GitHub, such as `you/mybot`, and copy the template in:

```sh
mkdir ~/mybot && cd ~/mybot && git init -b main
cp -r ~/nwn-server-playbook/templates/bot/. .
git add . && git commit -m "The bot, from the server playbook"
git remote add origin git@github.com:you/mybot.git
git push -u origin main
```

It has the code in `bot/`, its tests in `tests/`, the `Dockerfile`, a `compose.yaml` for running it without
Coolify, and `.env.example` with every setting. The versions of its two libraries are pinned in `requirements.txt`,
so the bot you tested is the bot that runs. To try the tests at home: `pip install -r requirements-test.txt && python
-m pytest -q`.

#### 5. ADAPT. Its settings

Change: every value. Copy [`.env.example`](../templates/bot/.env.example) to a file at home, fill it in, and keep it
private (`chmod 600`). The ones that matter:

| Setting | What |
|---|---|
| `DISCORD_TOKEN` | From step 2 |
| `GUILD_ID`, `DASHBOARD_CHANNEL_ID`, `CHANGELOG_CHANNEL_ID`, `STAFF_ROLE_ID` | The four numbers from step 3 ("guild" is Discord's word for a server) |
| `OPS_API_URL`, `OPS_API_KEY` | `http://10.77.0.1:8100` and the API's **team** key from chapter 9 |
| `GITHUB_WEBHOOK_SECRET` | A new secret, from `openssl rand -hex 32`. You'll type it into GitHub in step 8 |
| `SERVER_NAME` | The dashboard's title |

Leave `SYNC_COMMANDS` on. Step 7 says what it does.

#### 6. GENERIC. The application in Coolify

As in chapter 11's step 10, with these differences:

1. A read-only deploy key for `you/mybot`, made and added the same way.
2. In Coolify: **Projects**, a new project `bot`, add a resource, **Private Git Repository (with Deploy Key)**. The
   **control host** as its server (the bot sits beside the operations API), the key, the repository's SSH address,
   branch `main`, build pack **Dockerfile**, base directory `/`.
3. **Ports Exposes**: `9090`, the changelog's web server. **Domains**: `https://bot.example.org`.
4. **Persistent Storage**: add a volume named `bot-data`, mounted at `/data`. That's where the dashboard's message
   id lives.
5. **Environment variables**: **Developer View**, paste your settings from step 5, save. That shows them on your
   screen, so mind who's looking.

Then, as in chapter 11's step 11: point `bot.example.org` at the control host first, wait a few minutes, and only
then **Deploy**. And add the deploy webhook as in its step 12, so a merge to `you/mybot` redeploys the bot.

The bot reaches the operations API over the control host's private address from inside its container. Nothing on
the API's side needs opening: I checked from a container on Coolify's network.

#### 7. GENERIC. Check it

Within a minute of the deploy, the dashboard appears in `#server-status`. Watch it for two minutes: the time at the
bottom changes, and it stays one message.

The bot's log in Coolify should show three lines like these:

```
commands synced to the guild: restart, cancel-restart
webhook receiver on port 9090
dashboard posted: message 1234567890
```

**About `commands synced`.** Discord only shows a bot's slash commands once the bot has sent it the list. With
`SYNC_COMMANDS` on, this bot sends its two at every start, to your server only. That list **replaces** whatever
commands the same application had there before. If you ever run a second program on the same bot token, set
`SYNC_COMMANDS=false` in one of them, or the last one to start wins and the other's commands vanish.

Now try the buttons, at a quiet time. **Restart** asks for minutes of warning and a reason; give it 5, then press
**Cancel restart** straight away. Both answer you privately ("Restart in 5 minutes", "Restart cancelled"), and nobody
without the staff role gets further than "Only staff can do that."

Without Redis set up in chapter 9, players get no warning in the game: the API waits out the minutes and restarts
the container. The bot says so in its answer.

#### 8. GENERIC. The changelog webhook

For each repository whose merges your players should hear about (your module, your haks): **Settings**,
**Webhooks**, **Add webhook**:

- **Payload URL**: `https://bot.example.org/github`
- **Content type**: `application/json`
- **Secret**: the `GITHUB_WEBHOOK_SECRET` from step 5
- **Let me select individual events**: only **Pull requests**

GitHub sends a test at once. Under **Recent Deliveries** it should say `200`, and the bot's log `webhook ping`. Merge
a pull request, and within seconds the changelog channel gets a post: the repository, the number, the title, who
wrote it, and its labels.

A pull request labelled `no-changelog` gets no post: handy for tidying up nobody needs to read about. Anything that
isn't a merge (a pull request opened, labelled, or closed without merging) is answered `202` and ignored.

**The secret is what keeps this safe.** The bot's web server is on the internet, so anyone can send it a request. A
request whose signature doesn't match the secret is refused with `401`, and nothing is posted.

#### 9. GENERIC. Day to day

| You want to | Do |
|---|---|
| See the server | Look at `#server-status`. The time at the bottom says when it was last edited |
| Restart it | **Restart** under the dashboard, or `/restart` |
| Stop a restart you started | **Cancel restart**, or `/cancel-restart` |
| Post a merge the bot missed (it was down) | In the repository's **Recent Deliveries**, open the failed one and **Redeliver**. A merge is posted once, even if it's delivered twice |
| Move the dashboard | Change `DASHBOARD_CHANNEL_ID`, delete the old message, redeploy |
| Change the bot | A pull request on `you/mybot`, as for your website |

If the dashboard's time stops moving, the bot is down or can't reach Discord. Coolify shows it **unhealthy** after
about three minutes: the bot's health check fails when the dashboard hasn't been edited for three refreshes. If the
dashboard says it can't reach the operations API, look at the API first (chapter 9).

#### 10. LAYONARA-ONLY. A bigger bot

Ours also files bug reports into GitHub from Discord, carries chat between Discord and the game, keeps a channel
per character online, and turns a release into one long post with every change in it. Those are tier 3. They all
follow the pattern here: the bot asks the operations API, never the game host.

### The agent playbook

If you work with an AI agent, [`playbooks/10-discord-bot-tier2.md`](../playbooks/10-discord-bot-tier2.md) has these
steps in a fixed shape it can follow. It never sees the bot's token (you put the settings file in place), and it
asks before adding anything to your GitHub repositories or pressing **Restart**.

### Lessons

- **Give the bot the smallest key that does its job.** The team key covers everything this bot does. A bot is
  the piece most likely to have its settings copied around; if they leak, the worst case is a restart.
- **Edit one message, don't post new ones.** A channel with one dashboard is easy to read, and the bot keeps its
  message id on a volume so a redeploy carries on editing the same one. The test checked exactly that.
- **One token, one program.** Sending slash commands to Discord replaces the application's list. That's why
  `SYNC_COMMANDS` is a setting: for my test I ran the bot on a token another program already used, with that
  setting off and without Discord's live connection at all, so I couldn't disturb the other one.
- **Answer GitHub first, post second.** GitHub gives up on a webhook after 10 seconds. The bot checks the
  signature, answers, and posts from a queue, so a slow moment at Discord never shows up as a failed delivery.

### Tested

On 2026-11-26 with discord.py 2.7.1, aiohttp 3.14.5, Python 3.12, the operations API at its commit `d43a6f8`, and
Coolify 4.7.5, on a game host in the state tier 1 leaves it and a control host from chapter 3, both fresh Hetzner
cloud servers of the smallest shared type. The bot ran in Docker, from the template's `compose.yaml`, on my own
computer, against a real Discord server, in a private channel made for the test and deleted after it, and talked
to the API through an SSH tunnel to the control host:

- the dashboard posted, then edited in place every minute (the same message, checked by its id), with online,
  players, module, NWNX build and last restart, the time read from the game's log;
- the game stopped: the dashboard showed it offline 23 seconds later on one try and 59 on another, and online again
  with the new restart time after it started;
- a new container, rebuilt from the template, carried on editing the same message from its volume;
- the health check healthy while the dashboard was being edited;
- the changelog: a real GitHub webhook on a throwaway private repository, reaching my computer through a temporary
  forward on the control host; its ping answered `pong`, a merged pull request posted within seconds, one
  labelled `no-changelog` and the non-merge events answered `202` and not posted; a request signed with the wrong
  secret, and one with none, refused with `401`; a delivery sent twice posted once;
- Coolify: the template built by Coolify from a private repository with a deploy key, the Dockerfile build pack,
  port 9090, the `/data` volume and the settings pasted in bulk; and a container on Coolify's network on the
  control host reaching the API at `10.77.0.1:8100`.

Two things were tested with stand-ins, and you should know which:

- **The buttons and commands.** The only bot I could test with was already in use by another program, so the test
  ran with `DISCORD_GATEWAY=false` and `SYNC_COMMANDS=false`: the bot posted and edited over Discord's ordinary web
  API, without the live connection that delivers button presses. The button code itself was driven by stand-in
  interactions (fake button presses, with and without the staff role) against the real operations API: a
  non-staff press turned away; **Restart** with 1 minute, the dashboard showing the restart in progress, the game
  restarted at zero and the dashboard showing the new restart time; and a restart cancelled 15 seconds in, with
  the game left running. The template's tests cover the same with a fake API.
- **The bot in Coolify.** Coolify built and started it, but with a made-up token, since the real one stayed on my
  computer: Discord refused it, as it should. So the name and certificate in step 6, and a merged change
  redeploying the bot, were not tested for the bot; chapter 11 tests both for the website, the same way.

Not tested: real button presses and slash commands in Discord, the command sync against a fresh bot, and Redis's
in-game countdown (chapter 9's).
