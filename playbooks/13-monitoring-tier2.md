# Playbook 13, tier 2. An outside watchdog and one alert channel

For an agent. The chapter for people is [`chapters/13-monitoring.md`](../chapters/13-monitoring.md), section
"Tier 2". Follow the steps in order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `GAME` | The game host's public address or name, the one players use | none: a person gives it |
| `CONTROL` | The control host's public address | none: a person gives it |
| `GAME_WG` | The game host's private address | `10.77.0.2` |
| `CONTROL_WG` | The control host's private address | `10.77.0.1` |
| `SITE_URL` | The website's address, such as `https://www.example.org/` | none: a person gives it |
| `SITE_TEXT` | A few words that are on the page | none: a person gives it, or empty |
| `WORLD` | What the messages start with, such as `My World watchdog` | none: a person gives it |
| `DEPLOY_USER` | The deploy user on both machines | `nwn` |

Secrets: the webhook address. A person makes the webhook (chapter step 2) and places it on the control host
themselves with the chapter's step 3 command (`read -rs`); it ends up in `/etc/nwn-watchdog/webhook`. Never read,
print or copy that file. The watchdog's SSH private key is made on the control host and never leaves it.

## Preconditions

```sh
ssh $DEPLOY_USER@$CONTROL "ping -c 2 -q $GAME_WG | grep -o ' 0% packet loss'; test -e /usr/local/bin/nwn-watchdog && echo 'already installed' || echo 'not installed'"
ssh $DEPLOY_USER@$GAME 'ls game/backup.sh; systemctl is-enabled nwn-backup.timer; ls game/backups | grep -cE "^[0-9]{8}-[0-9]{6}$"'
templates/game/nwn-status.py $GAME
curl -s -m 10 -o /dev/null -w '%{http_code}\n' "$SITE_URL"
```

Success: `0% packet loss`, `not installed`; `game/backup.sh`, `enabled`, a number of at least 1; the game answers
with its module; `200`. If it is already installed, stop and ask.

## Steps

### 1. Install

```sh
scp -r templates/watchdog $DEPLOY_USER@$CONTROL:watchdog
ssh $DEPLOY_USER@$CONTROL 'sudo install -m 755 watchdog/nwn-watchdog.py /usr/local/bin/nwn-watchdog && sudo useradd --system --create-home --home-dir /var/lib/nwn-watchdog --shell /usr/sbin/nologin nwn-watchdog && sudo install -d -m 750 -g nwn-watchdog /etc/nwn-watchdog && sudo install -m 640 -g nwn-watchdog watchdog/watchdog.conf.example /etc/nwn-watchdog/watchdog.conf && sudo install -m 644 watchdog/nwn-watchdog.service watchdog/nwn-watchdog.timer /etc/systemd/system/ && sudo systemctl daemon-reload && echo installed'
```

Success: `installed`.

### 2. The webhook, placed by the person

Ask the person to run the chapter's step 3 command for the webhook (it prompts for the address) and tell you when
it says `saved`. Then:

```sh
ssh $DEPLOY_USER@$CONTROL 'sudo stat -c "%a %U %G %s" /etc/nwn-watchdog/webhook; sudo -u nwn-watchdog nwn-watchdog test'
```

Success: `640 root nwn-watchdog` and a size over 0, then `sent`. Ask the person to confirm the test message arrived
in their channel.

### 3. The settings

```sh
ssh $DEPLOY_USER@$CONTROL "sudo sed -i 's|^name = .*|name = $WORLD|; s|^host = game.example.org|host = $GAME|; s|^url = .*|url = $SITE_URL|; s|^expect =.*|expect = $SITE_TEXT|; s|^ssh = .*|ssh = $DEPLOY_USER@$GAME_WG|' /etc/nwn-watchdog/watchdog.conf && sudo grep -E '^(name|host|url|expect|ssh) ' /etc/nwn-watchdog/watchdog.conf"
```

Success: the five lines with the inputs' values.

### 4. The game host's report and its locked key

```sh
scp templates/watchdog/watchdog-report.sh $DEPLOY_USER@$GAME:game/
ssh $DEPLOY_USER@$GAME 'chmod 755 game/watchdog-report.sh && game/watchdog-report.sh'
ssh $DEPLOY_USER@$CONTROL 'sudo -u nwn-watchdog sh -c "mkdir -p -m 700 ~/.ssh && ssh-keygen -q -t ed25519 -N \"\" -C nwn-watchdog -f ~/.ssh/id_ed25519" && sudo cat /var/lib/nwn-watchdog/.ssh/id_ed25519.pub' > watchdog.pub
{ printf 'restrict,from="%s",command="/home/%s/game/watchdog-report.sh" ' $CONTROL_WG $DEPLOY_USER; cat watchdog.pub; } | ssh $DEPLOY_USER@$GAME 'cat >> ~/.ssh/authorized_keys' && rm watchdog.pub
ssh $DEPLOY_USER@$GAME 'cat /etc/ssh/ssh_host_ed25519_key.pub' | awk -v h=$GAME_WG '{print h, $1, $2}' | ssh $DEPLOY_USER@$CONTROL 'sudo -u nwn-watchdog sh -c "cat >> ~/.ssh/known_hosts"'
ssh $DEPLOY_USER@$CONTROL "sudo -u nwn-watchdog ssh -T -o BatchMode=yes $DEPLOY_USER@$GAME_WG; sudo -u nwn-watchdog ssh -T -o BatchMode=yes $DEPLOY_USER@$GAME_WG 'cat /etc/passwd' | head -1"
```

Success: the report (`disk <n> /` and `backup <stamp>`) from the game host; then the same report from the control
host, and once more its first line, `disk <n> /`, where `/etc/passwd` was asked for: the key runs the report
whatever is asked.

### 5. Look, then start

```sh
ssh $DEPLOY_USER@$CONTROL 'sudo -u nwn-watchdog nwn-watchdog status'
```

Success: six lines, each starting with `ok` (seven, with `game host borg backup`, once chapter 12's borg
backup has run with its current script). Any `FAIL`: report it to the person and stop; do not start the timer
with a failing check.

```sh
ssh $DEPLOY_USER@$CONTROL 'sudo systemctl enable --now nwn-watchdog.timer 2>&1 | tail -1; systemctl is-active nwn-watchdog.timer'
```

Success: `active`.

## Verify

Within three minutes:

```sh
ssh $DEPLOY_USER@$CONTROL 'sudo journalctl -u nwn-watchdog --no-pager -o cat | grep -E "^(started|still) watching|checks, " | tail -2'
```

Success: `started watching 6 checks: all passing` and `6 checks, 0 failing` (7 with the borg line of step 5). Ask the person to confirm the same
message arrived in their channel.

To prove an alert end to end without touching the game, add a check that cannot pass, wait for one alert, then
remove it and wait for one recovery:

```sh
ssh $DEPLOY_USER@$CONTROL 'printf "\n[drill]\ncheck = https\nurl = https://localhost:1/\n" | sudo tee -a /etc/nwn-watchdog/watchdog.conf >/dev/null; echo added'
```

After about five minutes, `journalctl` as above shows `ALERT drill: no answer (...)` once. Then:

```sh
ssh $DEPLOY_USER@$CONTROL "sudo sed -i '/^\[drill\]/,\$d' /etc/nwn-watchdog/watchdog.conf; sudo sed -i -e :a -e '/^\n*\$/{\$d;N;ba' -e '}' /etc/nwn-watchdog/watchdog.conf; sudo -u nwn-watchdog nwn-watchdog status | grep -c drill"
```

Success: `0`. A check that is removed from the settings sends no "OK": the next run forgets it quietly.

## Roll back

```sh
ssh $DEPLOY_USER@$CONTROL 'sudo systemctl disable --now nwn-watchdog.timer; sudo rm -f /etc/systemd/system/nwn-watchdog.{service,timer} /usr/local/bin/nwn-watchdog; sudo systemctl daemon-reload; sudo userdel -r nwn-watchdog; sudo rm -rf /etc/nwn-watchdog; echo removed'
ssh $DEPLOY_USER@$GAME 'sed -i "/ nwn-watchdog$/d" ~/.ssh/authorized_keys; rm -f game/watchdog-report.sh; grep -c nwn-watchdog ~/.ssh/authorized_keys'
```

Success: `removed`, then `0`. Nothing on the game host changes except the one key line and the report script. The
webhook itself is the person's: they delete it in Discord if they want it gone.

Clearing the watchdog's memory only (all checks start fresh, a new "started watching" message follows):
`ssh $DEPLOY_USER@$CONTROL 'sudo rm /var/lib/nwn-watchdog/state.json'`.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- making, reading, printing or replacing the webhook address, or choosing the channel;
- the watchdog already installed, or `/etc/nwn-watchdog` already there;
- a `FAIL` in step 5's `status`;
- stopping the game, the website or a backup to test an alert: use the Verify drill instead;
- `pause` for longer than the person asked for, or a pause that nobody asked for;
- an `authorized_keys` line for the watchdog without `restrict`, `from=` and `command=`.
