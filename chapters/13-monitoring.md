# Chapter 13. Monitoring and alerting

**Status:** tier 2 is written and tested. Tier 1 is covered by chapter 4: the game's container checks itself every
30 seconds, and `docker compose ps` shows you the answer. Tier 3 (the game's own numbers in dashboards, its logs
in one place, and request traces) is not written yet.

**Tier 1, in one paragraph.** With one machine and one person, [chapter 4's health check](04-game-server.md#4-generic-start-it)
is enough: the container asks its own server the question a player's game asks, and shows `(healthy)` when the
answer comes back. It tells you the state when you look. It doesn't tell you when you're not looking, and it can't
see anything from outside the machine. That's what tier 2 adds.

---

## Tier 2. An outside watchdog and one alert channel

### What you learn

How to be told, on your phone, when your game stops answering, before a player has to tell you. And just as
important: how to be told once, not every two minutes, and to hear when it's fine again.

When you're done, you'll have:

- a small **watchdog** on the control host, a script and a timer, that every two minutes asks the game the
  question a player's game asks, fetches your website, and looks at its certificate;
- the game host's **disk space and last night's backup** reported to it over the private network, by a script
  that can do nothing else;
- **one alert channel**, a Discord webhook, where every alert arrives: one message when something breaks, one when
  it's fixed, and a weekly "still watching" so silence means something;
- a **pause** for planned work, so a restart you meant doesn't wake anyone.

**Time:** about twenty minutes. The watchdog is one Python file with nothing to install; Ubuntu already has Python.

### What Layonara does

- **The watchdog lives outside all our machines,** as a small Cloudflare Worker on the free plan. Every five minutes
  it makes eight checks in parallel: the game (through Beamdog's public server list), the website, a page that
  needs the website's database, the forum, the wiki, the sign-in service, the NWSync server and Coolify.
- **An alert goes out after two failures in a row**, so about ten minutes, once per outage. One "back up" message
  follows, with how long it was down. Everything that changed in one run goes into one message.
- **Red alerts mention our admins; recoveries mention nobody.**
- **A pause key** with an expiry time keeps it quiet during planned work, and lifts itself.
- **A weekly message on Mondays** lists the checks, anything down, and the game's player count.
- **One Discord webhook for every alert** we have: the watchdog, the backups' own failure messages, a watcher
  that complains when a backup is more than 36 hours old, and the alert rule in our dashboards.

Our Worker reads the game's state from Beamdog's server list, because that's what a Worker can reach: Workers
can't send the UDP question a game server answers. This chapter's watchdog asks the game itself, which works
whether or not you're in the public list, and runs on a machine you already have.

### The human playbook

You need chapter 1's tier 2 (a control host, and the private network between it and the game host), and chapter
12's nightly backup on the game host. The examples use `CONTROL` and `GAME` for the two machines' public addresses,
`10.77.0.1` and `10.77.0.2` for their private ones, and `www.example.org` for your website.

The files are in [`templates/watchdog`](../templates/watchdog): the watchdog itself, its settings, a timer, and the
small report script for the game host. They're short, and the watchdog's first lines explain how it behaves.

#### 1. GENERIC. Know what it watches, and from where

| Check | How | Fails when |
|---|---|---|
| `game` | the game's own UDP question, to its public address, up to three tries | no answer in about 9 seconds |
| `website` | an HTTPS request for your page | anything but 200, or the page lacks words you name |
| `website certificate` | the certificate the page is served with | fewer than 14 days left, or not valid |
| `game host` | an SSH call over the private network | the game host doesn't answer it |
| `game host disk /` | the report from the game host | 90% full or more |
| `game host backup` | the report from the game host | the newest backup is more than 26 hours old |

The watchdog runs on the control host, so it sees the game from outside, across the internet, the way your players
do. If the whole game host stops, you hear about it twice in one message: the game and the report.

It is deliberately not a Coolify service. It's a plain timer on the control host, so a problem with Coolify, or
with Docker, can't silence it.

What it can't do is watch the machine it runs on. If the control host goes away, the watchdog goes with it, and
says nothing. The weekly message is there for that: if Monday comes and nothing arrives, look. Step 9 shows a
second, small copy on the game host that watches the control host back, if you'd like to close that gap properly.

#### 2. ADAPT. Make the alert channel

Change: the channel, if you'd rather not use Discord (step 8).

In Discord: your server's settings, **Integrations**, **Webhooks**, **New Webhook**. Give it a name such as
`Alerts`, choose a channel only your staff can see, and **Copy Webhook URL**.

That address is a password of sorts: anyone who has it can post in that channel. Keep it out of git and out of
chat. If it ever leaks, **Delete Webhook** on the same page and make a new one.

#### 3. GENERIC. Install it on the control host

From this repository, on your own computer:

```sh
scp -r templates/watchdog nwn@CONTROL:watchdog
ssh nwn@CONTROL 'sudo install -m 755 watchdog/nwn-watchdog.py /usr/local/bin/nwn-watchdog && sudo useradd --system --create-home --home-dir /var/lib/nwn-watchdog --shell /usr/sbin/nologin nwn-watchdog && sudo install -d -m 750 -g nwn-watchdog /etc/nwn-watchdog && sudo install -m 640 -g nwn-watchdog watchdog/watchdog.conf.example /etc/nwn-watchdog/watchdog.conf && sudo install -m 644 watchdog/nwn-watchdog.service watchdog/nwn-watchdog.timer /etc/systemd/system/ && sudo systemctl daemon-reload && echo installed'
```

It runs as a user of its own, `nwn-watchdog`, which can read its settings and write its memory in
`/var/lib/nwn-watchdog`, and nothing else.

Then the webhook address. This reads it from your keyboard, so it never lands in your shell's history:

```sh
ssh nwn@CONTROL 'read -rs -p "Webhook address: " u; echo; printf "%s\n" "$u" | sudo install -m 640 -g nwn-watchdog /dev/stdin /etc/nwn-watchdog/webhook && echo saved'
```

And the first message, to see the road works:

```sh
ssh nwn@CONTROL 'sudo -u nwn-watchdog nwn-watchdog test'
```

It prints `sent`, and the channel shows "test message from ...: alerts arrive here".

#### 4. ADAPT. Tell it what to watch

Change: the name, the game's address, the website's address, and a few words from your page.

```sh
ssh -t nwn@CONTROL 'sudo nano /etc/nwn-watchdog/watchdog.conf'
```

The file explains each line. Use the game's **public** name or address, the one players type, so the check takes
their road. The `expect` line is worth filling in: a few words from your page, so an error page that answers
politely with 200 still counts as down.

#### 5. GENERIC. Let the game host report its disk and backup

The watchdog needs two facts that only the game host knows. It gets them with an SSH key that can run one small
script, [`watchdog-report.sh`](../templates/watchdog/watchdog-report.sh), and nothing else: no shell, no files, no
tunnels, and only from the control host's private address.

The script goes beside the backup script on the game host:

```sh
scp templates/watchdog/watchdog-report.sh nwn@GAME:game/
ssh nwn@GAME 'chmod 755 game/watchdog-report.sh && game/watchdog-report.sh'
```

It prints something like `disk 17 /` and `backup 20261126-141703`.

Then the key. The first command makes it on the control host; the second puts it on the game host with its locks:
`restrict` (no shell, no forwarding), `from=` (only from the private address) and `command=` (only the report).
The third tells the watchdog the game host's own key, fetched from the game host itself, so it never has to trust
a first answer blindly.

```sh
ssh nwn@CONTROL 'sudo -u nwn-watchdog sh -c "mkdir -p -m 700 ~/.ssh && ssh-keygen -q -t ed25519 -N \"\" -C nwn-watchdog -f ~/.ssh/id_ed25519" && sudo cat /var/lib/nwn-watchdog/.ssh/id_ed25519.pub' > watchdog.pub
{ printf 'restrict,from="10.77.0.1",command="/home/nwn/game/watchdog-report.sh" '; cat watchdog.pub; } | ssh nwn@GAME 'cat >> ~/.ssh/authorized_keys' && rm watchdog.pub
ssh nwn@GAME 'cat /etc/ssh/ssh_host_ed25519_key.pub' | awk '{print "10.77.0.2", $1, $2}' | ssh nwn@CONTROL 'sudo -u nwn-watchdog sh -c "cat >> ~/.ssh/known_hosts"'
```

The public key is safe to carry around like this; the private half never leaves the control host.

#### 6. GENERIC. Look, then start the timer

`status` runs every check once and sends nothing:

```sh
ssh nwn@CONTROL 'sudo -u nwn-watchdog nwn-watchdog status'
```

You'd like six lines, each starting with `ok`. A `FAIL` says what it saw: fix that first, or you'll get an alert
for it a few minutes after you start. Then:

```sh
ssh nwn@CONTROL 'sudo systemctl enable --now nwn-watchdog.timer'
```

Within two minutes the channel says "started watching 6 checks: all passing". That's the last you'll hear from it
until something changes, or until next week.

#### 7. GENERIC. What an alert looks like, and what to do with it

When I stopped the game on the test, this arrived three and a half minutes later:

```
**My World watchdog**
ALERT game: no answer from GAME port 5121 (failing since 2026-11-26 14:30 UTC)
```

and when it was back, one more:

```
**My World watchdog**
OK game: passing again, after 6 min
```

Nothing in between, however long it's down. The other checks read the same way: `website: answered 502`,
`website certificate: expires in 2.9 days`, `game host disk /: 95% full`, `game host backup: the newest is 30
hours old`.

Before planned work, such as a release or a reboot, pause it, and it lifts itself when the time is up:

```sh
ssh nwn@CONTROL 'sudo -u nwn-watchdog nwn-watchdog pause 30'
```

If a run is under way, `pause` waits for it to finish, usually a few seconds, so the run can't undo it.
`resume` ends a pause early. Something that was already alerted before a pause still gets its "OK" afterwards.

If Discord can't be reached when there's news, nothing is marked as sent, and the next run tries again. On the
test, the stand-in refused two runs in a row; the third delivered both alerts, once.

Its log is the system journal: `sudo journalctl -u nwn-watchdog` on the control host shows every run.

#### 8. ADAPT. Another channel instead of Discord

Change: the `style` line in `watchdog.conf`, and the address in `/etc/nwn-watchdog/webhook`.

- `style = discord` (the default) sends `{"content": "..."}`, the shape Discord's webhooks take, with mentions
  switched off unless you set `mention_role`.
- `style = slack` sends `{"text": "..."}`, for a Slack incoming webhook, and for the many chat tools that copy
  Slack's shape.
- `style = plain` sends the message itself as the body, which suits ntfy and other push services: the webhook
  address is then your topic's address.

Then `nwn-watchdog test` again. If you want something else entirely, `send()` in the script is fifteen lines, and
it's the only place that knows about the channel.

To have your admins pinged on an alert, set `mention_role` to the role's id (in Discord, with Developer Mode on,
right-click the role and **Copy Role ID**). Alerts then mention that role and nobody else; "OK" messages mention no
one.

#### 9. ADAPT. Optional: let the game host watch back

Change: the website address, if your website is on the control host (chapter 11's tier 2).

The watchdog can't see its own machine go away. The tidy answer is a second copy on the game host, watching only
what lives on the control host: install it there as in step 3, and give it a `watchdog.conf` with one `https`
check, for your website or for anything else the control host serves. It costs the game a few milliseconds every
two minutes. Then whichever machine goes quiet, the other one says so.

#### 10. LAYONARA-ONLY. A watchdog on nobody's machine

Ours is a Cloudflare Worker, so it lives on none of our machines and watches all of them, and it watches the game
through Beamdog's list because a Worker can't send the game's UDP question. If you're already on Cloudflare, it's a
lovely next step. For two machines, the timer in this chapter is simpler, and it asks the game directly.

### The agent playbook

If you work with an AI agent, [`playbooks/13-monitoring-tier2.md`](../playbooks/13-monitoring-tier2.md) has these
steps in a fixed shape it can follow. You make the webhook and place its address yourself; the agent never sees it.

### Lessons

- **Once, then quiet, then "OK" (from our watchdog's design).** An alert that repeats every few minutes gets
  muted, and a muted channel is worse than none. Ours alerts once per outage and once on recovery, and the one in
  this chapter does the same. Two failures in a row before the first message keeps a single lost packet from
  waking anyone.
- **Watch from where your players are.** A check on the game host itself says the process is fine while a firewall
  rule, a provider's network or a full disk keeps every player out. Ask from another machine, over the public
  address.
- **Silence needs a heartbeat.** A watchdog that has stopped looks exactly like one with nothing to say. The weekly
  message turns silence into a signal.
- **A broken page can still answer 200.** A page that fills itself from a database can come back with a polite 200
  and nothing in it when the database is away, so our check for such a page looks for a piece of it, not only the
  status. That's the `expect` line.
- **Let the backup be checked by someone other than the backup.** A backup script can report its own failure, but
  not a run that never started: a stopped timer, a machine that was off at the time. Looking at the age of the
  newest backup catches both, which is why we have a watcher for exactly that.
- **A pause has to wait its turn (2026-11-26).** In this chapter's first version, a pause typed during a run was
  lost when that run saved its memory a few seconds later, and an "OK" arrived in the middle of planned work. The
  test caught it; now each command waits for the one before it.
- **One channel for everything.** Every alert we have goes to the same channel, so there's one place to look and
  one notification to keep switched on.

### Tested

On 2026-11-26, on two fresh Hetzner cloud servers of the smallest shared type in the same location: a game host in
the state tier 1 leaves it (game with `nwnxee/unified`, database, an example module, the nightly backup, and the
one-page website with a Let's Encrypt certificate), and a second machine as the control host, joined by chapter 1's
private network. Ubuntu 26.04.1 with its Python 3.14.4, systemd 259 and OpenSSH 10.2.

Discord itself was replaced by a stand-in I ran on the control host: a small HTTP receiver that checked every
message against Discord's documentation for executing a webhook (JSON, a `content` of at most 2000 characters,
`allowed_mentions` with `parse`, `roles` or `users`, and a User-Agent), answered 204 as Discord does, and kept a
log.

What I tested, each with the messages it sent checked in the stand-in's log:

- the whole install twice, the second time from nothing after the Roll back, following the agent playbook
  command by command: `test` delivered, `status` showed six `ok` lines, and "started watching 6 checks: all
  passing" arrived within two minutes of starting the timer;
- **the game stopped:** one alert three and a half minutes later, and one "OK" when it was back. Left down for about
  half an hour another time, it still sent exactly one alert;
- **the website stopped** (its web server switched off): one alert, then one "OK";
- **a certificate with 3 days left,** from a test authority the watchdog was told to trust for the test, served on a
  spare port: `expires in 3.0 days` in the same message as the website alert, and "OK" for both when they were back;
- **a full disk and a missed backup** on the game host (a spare file filling the disk to 94%, and the newest backup
  made 30 hours old), with the stand-in refusing the first two attempts with 503: nothing was marked as sent, and
  the third run delivered both alerts in one message; both "OK"s followed;
- **the pause:** the game stopped and started again inside a pause sent nothing at all; a game already alerted,
  then paused and brought back during the pause, got its "OK" on the first run after the pause. The first version
  lost a pause typed during a run (see the Lessons); the fixed one was tested by pausing two seconds into a run;
- the agent playbook's drill: one alert, then the check removed and forgotten without an "OK";
- the locked key: refused from the control host's public address, a request for `/etc/passwd` answered with the
  report, and a tunnel through it refused;
- `style = slack`, `style = plain` and `mention_role`, against the stand-in.

Not tested: a real Discord channel (the stand-in checked the same rules Discord documents), real Slack or ntfy,
step 9's second copy on the game host, and a week of running for the weekly message: I tested its first message,
and its timing is one comparison in the script.
