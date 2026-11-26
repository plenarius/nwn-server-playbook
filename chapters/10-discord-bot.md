# Chapter 10. The Discord bot

**Status:** tiers 2 and 3 are written and tested. Tier 1 doesn't need a bot. Tier 3 adds reports from Discord, a
chat bridge with the game and a roster of who's online.

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
  players, module, NWNX build and last restart;
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

After that test the operations API began reporting `started_at`, the time the game's container last started, in
its status, and the dashboard's "Last restart" switched to it from a time read out of the game's log (it shows
"unknown" when the API can't tell). That change is covered by the template's tests, written against the API's
documented answer at its commit `7b05e20`, not by a second run in Discord.

Not tested: real button presses and slash commands in Discord, the command sync against a fresh bot, and Redis's
in-game countdown (chapter 9's).

## Tier 3. Reports, a chat bridge and a roster

### What you learn

How to let players reach your team, and each other, without leaving Discord, and without the bot ever getting more
power than the job needs. Three parts, each off until you give it a channel:

- **Reports.** A player types `/report`, fills in a short form, and the bot files it as an issue in a private
  GitHub repository and opens a private thread for them. When someone on the team answers on the issue with a
  comment that starts `To reporter:`, the answer appears in that thread. The player never needs a GitHub account,
  and nothing on GitHub says who they are.
- **A chat bridge.** One Discord channel and the game's shout channel, both ways. Lines from the game come out
  of a small table; lines from Discord go in as jobs on chapter 5's work queue. Both directions are rate-limited,
  and mentions are stripped both ways, so nobody in the game can ping `@everyone` on your Discord.
- **A roster.** One message, edited every minute, with the names of everyone in the game, from the operations
  API's read-only roster route.

When you're done, you'll have:

- about 450 more lines of Python in your bot, with their tests;
- two migrations (`chat_out`, `online_players`) and five small scripts in your module, with four tests for
  chapter 6's test runner;
- a database account for the bot that may add jobs to the queue and read `chat_out`, nothing else;
- the operations API answering `GET /api/v1/server/online`, through a read-only database account.

**Time:** about an hour and a half: half an hour for the module side, the rest in Discord's and GitHub's settings.

### What Layonara does

- **Reports live in GitHub issues, and players talk to us in Discord threads.** Our bot files bug reports and
  feature requests from Discord, and keeps a thread per report in a forum channel. Comments meant for the player
  start with a fixed prefix and are copied to the thread; everything else stays between the team. Reports typed
  in the game arrive the same way, through a queue table.
- **Our chat bridge carries one in-game channel to one Discord channel** and back, in batches every few seconds,
  with mentions taken out on the way.
- **The roster is in the channel list.** Ours keeps one locked voice channel per character online, so the sidebar
  itself shows who's playing. It's lovely, and more moving parts, since Discord limits how often a channel
  can change; the one message here is the simple version, and a fine place to start.

This chapter's three parts are written fresh for the guide and are smaller than ours: one table and one form each,
and nothing you'd have to take out again.

### The human playbook

You need tier 2 of this chapter (the bot in Coolify, the webhook receiver at `https://bot.example.org/github`),
chapter 5's tier 3 (the work queue, the private database and `db-accounts.sh`), chapter 6's module repository with
its test runner, and chapter 9's operations API with its read key. The files are in
[`templates/bot`](../templates/bot) and [`templates/module/bot`](../templates/module/bot).

#### 11. GENERIC. Know the three paths

| Part | Path |
|---|---|
| Reports | Discord form → bot → GitHub issue. GitHub comment → webhook → bot → the reporter's private thread |
| Chat, game to Discord | A shout → NWNX_Chat → `chat_out` row → the bot reads new rows every 3 seconds → one post |
| Chat, Discord to game | A message → bot → a `chat` job on `work_queue` → the game's poller → every player's chat window |
| Roster | The game writes `online_players` every 30 seconds → the operations API reads it → the bot edits one message |

The bot still never touches the game host's files or its container. It reads and writes two tables through an
account made for it, and asks the operations API for the rest.

**Who knows who reported what?** Only the bot. It keeps each issue's number, the thread and the reporter's Discord
id in a small file on its `/data` volume. The issue on GitHub has the report's words and nothing else, so a private
repository you later open to helpers, or an AI agent that reads issues, never sees a player's Discord account.

#### 12. ADAPT. The module side

Change: the migration numbers, and the line in your `OnModuleLoad` script.

The two tables are migrations, like chapter 5's work queue. Copy them under your next two numbers:

```sh
cp ~/nwn-server-playbook/templates/module/bot/chat-out.sql ~/mymodule/migrations/0005-chat-out.sql
cp ~/nwn-server-playbook/templates/module/bot/online-players.sql ~/mymodule/migrations/0006-online-players.sql
```

Then the scripts into `src/nss/`, and the tests into `tests/nss/`:

```sh
cd ~/nwn-server-playbook/templates/module/bot
cp inc_bridge.nss chat_bridge.nss wq_chat.nss bridge_start.nss roster_poll.nss ~/mymodule/src/nss/
cp t_*.nss inc_bridge_t.nss ~/mymodule/tests/nss/
```

And one line at the end of your `OnModuleLoad` script, after chapter 5's `ExecuteScript("db_poll");`:

```c
ExecuteScript("bridge_start");
```

What they do:

| Script | Job |
|---|---|
| `bridge_start` | Registers the chat script with NWNX_Chat, removes `chat_out` rows older than a day, starts the roster |
| `chat_bridge` | NWNX_Chat runs it for every line said. Shouts from players and DMs go on to `inc_bridge` |
| `inc_bridge` | Takes out colour codes, cuts a line at 400 characters, lets 5 lines a minute per speaker through to Discord (they're told once when they hit it, and everyone in the game still hears them) |
| `wq_chat` | The `chat` job: shows `[Discord] Name: text` to every player. A line older than two minutes is dropped, so a game coming back from a restart doesn't read out old chat |
| `roster_poll` | Writes `online_players` again every 30 seconds, in one transaction, DMs marked |

**NWNX_Chat runs one chat script for the whole server.** If your module already registers one, don't register
`chat_bridge` too: call `Bridge_FromGame(oSpeaker, sMessage)` from yours, and leave that line out of
`bridge_start`.

Run the tests before you release (chapter 6): `tests/run.sh --filter t_bridge_,t_roster_`. Four tests, all
`PASS`. They shout as a creature, since the test server has no players.

#### 13. GENERIC. Switch on NWNX_Chat and UTF-8, and release

Add three lines to the game's `.env` on the game host:

```sh
NWNX_CHAT_SKIP=n
NWNX_SQL_USE_UTF8=true
NWNX_SQL_CHARACTER_SET=utf8mb4
```

The first turns on the chat plugin. The other two make text cross to the database as UTF-8, so a player's
`crème brûlée` reaches Discord as written, and an accent typed in Discord reaches the game. Then release as in
chapter 5, tier 2: tag your module and run `release.sh`. It makes the two tables, puts the module in place and
restarts the game. The game's log says `bridge_start: chat bridge and roster on`.

#### 14. GENERIC. An account for the bot

On the game host, from the game folder, with chapter 5's script. The password goes in on standard input:

```sh
openssl rand -hex 16   # into your password manager, then:
./db-accounts.sh bot botchat 10.77.0.1
./db-accounts.sh show botchat
```

`show` should list exactly two rights: `SELECT, INSERT (args, added_by, kind)` on `work_queue`, and `SELECT` on
`chat_out`. The account can't read your players' characters, can't change a job once it's added, and can only log
in from the control host's private address. I tried it from the game host's own address and it was refused.

#### 15. GENERIC. The roster in the operations API

The route is in the operations API from its pull request #6 on. It runs a query you give it, through a read-only
account, so you decide what it shows. Make the account as in chapter 5's step 28:

```sh
./db-accounts.sh reader opsreader 10.77.0.1
```

Then add these to the API's settings in Coolify (chapter 9) and redeploy it:

```sh
MYSQL_HOST=10.77.0.2
MYSQL_USER=opsreader
MYSQL_PASSWORD=...
ONLINE_SQL=SELECT name FROM online_players WHERE dm = 0 AND seen_at > NOW() - INTERVAL 90 SECOND ORDER BY name
```

The query leaves DMs out, so they aren't even counted, and leaves out rows older than 90 seconds, which belong to a
game that has stopped. Check it from the control host with the **read** key:

```sh
curl -s -H "Authorization: Bearer $READ_KEY" http://10.77.0.1:8100/api/v1/server/online
```

`{"count":0,"characters":[]}` with nobody in the game. Since the read key opens it, a public status page can show
the same list. The bot's team key opens everything the read key does.

#### 16. GENERIC. Discord: one switch, three channels

1. In the [Developer Portal](https://discord.com/developers/applications), on **Bot**, switch on **Message Content
   Intent**. The chat bridge needs it to read what people write in its channel; the bot asks for it only when
   the bridge is on.
2. Three channels:
   - `#reports`: where the private threads go. Players need **View Channel** and **Use Application Commands**;
     nobody needs to post in it. The bot needs **Create Private Threads**, **Send Messages in Threads** and
     **Manage Threads** (so it can still answer in a thread a moderator locked).
   - `#game-chat`: the bridge. Everyone who may talk to the game can post; the bot needs **Add Reactions** too.
   - `#whos-online`: the roster, like `#server-status`: everyone reads, only the bot posts.
3. **Copy ID** for all three.

People with **Manage Threads** on `#reports` see every report thread. Give that to your staff role, and to nobody
else.

#### 17. ADAPT. The reports repository and its token

Change: the repository's name.

1. A new **private** repository on GitHub for reports, such as `you/reports`. Keeping them apart from your module
   lets you open the code to helpers later without opening the reports.
2. A **fine-grained token** (GitHub, **Settings**, **Developer settings**, **Fine-grained tokens**): only that one
   repository, permission **Issues: Read and write**, nothing else. If it ever leaks, the most anyone can do is
   file and edit issues there.
3. On that repository, **Settings**, **Webhooks**, **Add webhook**: the same URL and secret as the changelog's
   (step 8), and under **Let me select individual events** only **Issues** and **Issue comments**.

The bot files each report with the labels `bug` or `idea`, and `from-discord`. GitHub makes a label the first time
it's used.

#### 18. ADAPT. The bot's settings, and deploy

Change: the ids, the repository, and the passwords. Add to the bot's environment variables in Coolify (the whole
list, with comments, is at the end of [`.env.example`](../templates/bot/.env.example)):

| Setting | What |
|---|---|
| `REPORTS_CHANNEL_ID`, `REPORTS_REPO`, `GITHUB_TOKEN` | `#reports`, `you/reports` and the token from step 17 |
| `BRIDGE_CHANNEL_ID`, `BRIDGE_DB_USER`, `BRIDGE_DB_PASSWORD` | `#game-chat`, `botchat` and its password from step 14. The address defaults to `10.77.0.2:3306` |
| `ROSTER_CHANNEL_ID` | `#whos-online` |

Merge the new bot code (step 19 says how to bring it in) and Coolify redeploys. With `SYNC_COMMANDS` on, the log
now says `commands synced to the guild: restart, cancel-restart, report`, then `chat bridge on`, and the roster
appears in its channel within a minute.

**Missing a setting?** The bot refuses to start and names it, for example `REPORTS_CHANNEL_ID is set, so
REPORTS_REPO (owner/name), GITHUB_TOKEN and GITHUB_WEBHOOK_SECRET must be too`. That's on purpose: a half-set part
is worse than one that's off.

#### 19. GENERIC. Bring in the new code

The template's `bot/` gained `reports.py`, `bridge.py` and `roster.py`, and small changes to `__main__.py`,
`settings.py`, `changelog.py` and `ops_api.py`; `requirements.txt` gained `aiomysql`. In your bot's repository:

```sh
cp -r ~/nwn-server-playbook/templates/bot/. ~/mybot/
cd ~/mybot && git diff --stat && python -m pytest -q
```

If you changed the bot yourself since tier 2, the diff shows where the two meet. The tests should all pass before
you open the pull request.

#### 20. GENERIC. Check it

- **Reports.** Type `/report`, pick **Something is broken**, fill in the form. The answer, which only you see,
  says `Thanks! The team has it as report 1, and their answers will appear in #1 ...`. The thread is there, with
  you mentioned in it; the issue is on GitHub, without your name. Comment `To reporter: thank you, we're on it` on
  the issue: within seconds it's in the thread as **The team:** .... A comment without the prefix stays on GitHub.
  Close the issue and the thread gets a thank-you. A second report within ten minutes is gently refused.
- **The bridge.** Shout in the game: the line appears in `#game-chat` with your character's name. Write in
  `#game-chat`: it appears in the game as `[Discord] Your name: ...`. Shout `@everyone` in the game: it arrives
  as plain text, and nobody is pinged.
- **The roster.** Log in: within a minute and a half your character's name is in `#whos-online`. A DM isn't listed.

#### 21. GENERIC. Day to day

| You want to | Do |
|---|---|
| Answer a reporter | A comment on the issue starting `To reporter:` |
| Talk to the team about a report | Any other comment: it stays on GitHub |
| Find who sent a report | Ask the bot's file, not GitHub. In the bot's terminal in Coolify: `python -c "import sqlite3; print(sqlite3.connect('/data/reports.db').execute('SELECT reporter_id FROM reports WHERE issue = 12').fetchone())"`, then search that id in Discord. Do it only when you need to |
| Quiet the bridge for a while | Take `BRIDGE_CHANNEL_ID` out and redeploy; the game keeps writing `chat_out`, and the bot starts from the newest line when it's back, so nobody is flooded with old chat |
| See what was said | `chat_out` keeps a day of it. It is your players' chat, so treat it like any other log |
| Move a channel | Change its id and redeploy. The roster posts a fresh message; delete the old one |

A late answer to an old report still arrives: posting in an archived thread opens it again. If GitHub couldn't
reach the bot, use **Redeliver** on the webhook: the bot posts each comment and each close once.

#### 22. LAYONARA-ONLY. More from the same parts

Ours also lets a player answer in their thread and turns that into an issue comment, adopts threads players open
by hand as reports, and takes reports typed in the game through a queue table. Each is the same pattern again: a
table or an issue in the middle, and the bot carrying words across with the ids kept out of sight.

### The agent playbook

[`playbooks/10-discord-bot-tier3.md`](../playbooks/10-discord-bot-tier3.md) has these steps for an AI agent. It
never sees the bot's token, the GitHub token or the database passwords (you put them in place), and it asks before
anything that posts in a channel players can read.

### Lessons

- **Keep who-said-what with the bot, not with the issue.** The issue tracker is the thing you'll most want to share
  later, with helpers and with tools. If it never had the reporter's Discord id, sharing it is easy.
- **Make every crossing plain text.** Discord turns `@everyone`, `<@123>` and `**bold**` into pings and formatting;
  the game turns `<c...>` into colours. The bridge takes each side's codes out before the other sees them, and
  posts with mentions switched off as well, so a slip in one place is caught by the other.
- **Rate-limit on both sides of the wire.** The game holds back a player's sixth shout a minute before it ever
  reaches the database; the bot holds back the sixth message in 30 seconds before it reaches the queue, and caps
  its own posts so Discord never has to slow it down. A busy evening becomes "and more" rather than a flood.
- **Let a table carry the chat.** Neither side waits for the other. When I restarted the database in the test,
  the bot logged a warning every few seconds and carried on where it left off as soon as it was back; nothing was
  lost and nothing was posted twice.
- **One chat script.** NWNX_Chat has a single hook for the whole server. If two systems each register theirs, the
  last one wins silently, so the bridge is a function you call from yours.

### Tested

On 2026-11-26 with discord.py 2.7.1, aiohttp 3.14.5, aiomysql 0.3.2, Python 3.12, NWNX `ed79330`, MariaDB 11.8,
and the operations API at its commit `5d4ff2a`
([nwn-ops-api#6](https://github.com/plenarius/nwn-ops-api/pull/6)), on a game host in the state chapter 5's tier
3 leaves it and a control host on the private network, both fresh Hetzner cloud servers of the smallest shared
type. As in tier 2, the bot ran in Docker from the template on my own computer, against a real Discord server, in a
private channel made for the test and deleted after it, and reached the database and the API through SSH tunnels
to the control host, so the database saw it come from the control host's address:

- the module: the two migrations released with `release.sh`; the four new tests and the four old ones passing on
  the game host with chapter 6's runner; the live game writing `online_players` every 30 seconds;
- game to Discord: a shout through NWNX_Chat in the live game became one post, with its colour codes gone,
  `@everyone` and `<@123>` shown as plain text and nobody pinged, `**bold**` shown as typed, and `café` intact; a
  crowd of shouts at once became at most three posts with "and more"; the database restarted under it, and the
  next shout arrived without a duplicate;
- Discord to game: a message with a mention, `@everyone`, a custom emoji, two lines, colour codes and accents
  became one plain line in the queue (`hello @Mira! everyone see :wave: crème brûlée ☃ line two x`), and the live
  game ran it; seven messages from one person in a row put five in the queue and an hourglass on the rest; the
  bot's account refused from any address but the control host's;
- reports: a report filed as a real issue in a throwaway private repository with no Discord id in it, a private
  thread made with the reporter mentioned, a `To reporter:` comment in the thread within seconds through a real
  GitHub webhook, a comment without the prefix (with `@everyone` in it) left on GitHub, the close posted, a post
  in an archived thread opening it again, and a second report within the cooldown refused;
- the roster: the API's route on the read key, refused without it, and the bot's message edited in place every
  minute: empty, then with two names and a DM left out, with a name containing `@everyone` shown as plain text.

What ran with stand-ins, and you should know which:

- **The gateway.** As in tier 2, the bot shared its token with another program, so it ran with
  `DISCORD_GATEWAY=false` and `SYNC_COMMANDS=false`. Discord messages for the bridge and the report form were
  stand-in objects passed to the bot's own handlers, while everything they did (the queue, GitHub, the threads, the
  posts) was real. Not tested: the `/report` command and its form in a real Discord app, a real message reaching
  `on_message`, and the Message Content intent.
- **The reporter.** The only Discord account in the test was the bot itself, so it stood in as the reporter. A
  player being added to the thread and getting the notification was not tested.
- **The players.** No game client connected. The shouts came from a creature through NWNX_Chat's own send call,
  the same hook a player's shout goes through, and a line from Discord was shown to nobody (`shown to 0`). A
  player's real shout, and a line from Discord on a player's screen, were not tested.
- **Coolify.** The new settings were not deployed through Coolify; tier 2's test covers the bot in Coolify.
