# Playbook 12, tier 3. The character vault's history, and a watch on both histories

For an agent. The chapter for people is [`chapters/12-backups.md`](../chapters/12-backups.md), section "Tier 3".
Follow the steps in order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `GAME` | The game host's public address | none: a person gives it |
| `CONTROL` | The control host's public address | none: a person gives it |
| `DEPLOY_USER` | The deploy user on both machines | `nwn` |
| `VAULT_REMOTE` | The history's repository, as an SSH address, such as `git@github.com:your-name/my-world-vault.git` | none: a person gives it |
| `GIT_HOST` | The host in `VAULT_REMOTE` | `github.com` |
| `GIT_HOST_FINGERPRINT` | That host's published Ed25519 fingerprint. GitHub's: `SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU` | none: a person confirms it |

Secrets: the deploy key's private half is made on the game host in `/root/.ssh/vault-history` and never leaves it.
Never print it. The public half is not secret. The repository holds players' characters: never clone it to the
person's computer or anywhere else, and never print a character file.

A person, not the agent, does these on GitHub: makes the private repository, adds the deploy key with write
access, and makes the ruleset (chapter, steps 23 and 25).

## Preconditions

```sh
ssh $DEPLOY_USER@$GAME 'sudo test -d game/home/servervault && echo vault; test -e game/vault-history && echo "history exists" || echo "no history"; test -e /usr/local/sbin/nwn-borg-backup && echo borg; systemctl is-active borg-backup.timer'
ssh $DEPLOY_USER@$CONTROL 'test -x /usr/local/bin/nwn-watchdog && echo watchdog; systemctl is-active nwn-watchdog.timer'
```

Success: `vault`, `no history`, `borg`, `active`; `watchdog`, `active`. If `history exists`, stop and ask. Chapter
12's tier 2 and chapter 13's tier 2 must be done first.

## Steps

### 1. Install the script, its timer and the key

```sh
scp -r templates/backup $DEPLOY_USER@$GAME:backup
ssh $DEPLOY_USER@$GAME "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git rsync >/dev/null && cd backup && sudo install -m 755 vault-history.sh /usr/local/sbin/nwn-vault-history && sudo install -m 644 vault-history.service vault-history.timer /etc/systemd/system/ && sudo systemctl daemon-reload && sudo test -e /root/.ssh/vault-history || sudo ssh-keygen -q -t ed25519 -N '' -C vault-history -f /root/.ssh/vault-history; sudo sh -c 'ssh-keyscan -t ed25519 $GIT_HOST > /root/.ssh/vault-history.known_hosts 2>/dev/null' && sudo ssh-keygen -lf /root/.ssh/vault-history.known_hosts | awk '{print \$2}'; sudo cat /root/.ssh/vault-history.pub"
```

Success: the fingerprint, exactly `$GIT_HOST_FINGERPRINT`, then one line starting `ssh-ed25519` and ending
`vault-history`. If the fingerprint differs, stop and ask.

Give the person the public key line and ask them to add it to the repository as a deploy key **with write
access** (chapter, step 23). Wait until they say it's done.

### 2. The first commit

```sh
ssh $DEPLOY_USER@$GAME "cd game && sudo git init -q -b main vault-history && sudo git -C vault-history remote add origin $VAULT_REMOTE && sudo nwn-vault-history && cat vault-history.ok"
```

Success: `committed N file(s): <commit>` with N the number of characters, `pushed`, and a time such as
`20261126-174816`. `Permission denied (publickey)`: the deploy key is missing or lacks write access; ask the person.

### 3. The timer

```sh
ssh $DEPLOY_USER@$GAME 'sudo systemctl enable --now vault-history.timer 2>/dev/null; systemctl is-active vault-history.timer; sleep 3; systemctl list-timers vault-history.timer --no-pager | sed -n 2p'
```

Success: `active`, and a line whose first time is within the next 31 minutes. If a half hour passed since the
last run (as after a reinstall), the timer also runs once straight away; that's expected.

### 4. The ruleset, made by the person

Ask the person to make the ruleset of the chapter's step 25 (block force pushes, restrict deletions, default
branch), or to tell you they have no paid plan for it. Then read the branch's rules, without changing anything
(`OWNER/REPO` from `VAULT_REMOTE`; needs the person's `gh` login):

```sh
gh api repos/OWNER/REPO/rules/branches/main --jq '.[].type'
```

Success: `non_fast_forward` and `deletion` among the lines. Never test it with a real force-push: without the rule,
that would erase the history. If there is no ruleset, say in your report that the borg backup is the only copy
that can't be rewritten.

### 5. The watch: new report, backup script and watchdog

```sh
scp templates/watchdog/watchdog-report.sh $DEPLOY_USER@$GAME:game/
scp templates/backup/borg-backup.sh $DEPLOY_USER@$GAME:backup/
ssh $DEPLOY_USER@$GAME 'sudo install -m 755 backup/borg-backup.sh /usr/local/sbin/nwn-borg-backup && sudo nwn-borg-backup 2>&1 | tail -1 && game/watchdog-report.sh'
scp templates/watchdog/nwn-watchdog.py $DEPLOY_USER@$CONTROL:
ssh $DEPLOY_USER@$CONTROL 'sudo install -m 755 nwn-watchdog.py /usr/local/bin/nwn-watchdog && rm nwn-watchdog.py && (sudo grep -q "^vault_hours" /etc/nwn-watchdog/watchdog.conf || printf "borg_hours = 26\nvault_hours = 2\n" | sudo sed -i "/^backup_hours/r /dev/stdin" /etc/nwn-watchdog/watchdog.conf) && sudo -u nwn-watchdog nwn-watchdog status'
```

Success: `backup made: ...`; the report's last two lines `borg <time>` and `vault <time>`; then `status` with every
line `ok`, two of them `game host borg backup` and `game host vault history`.

## Verify

The history moves, and a restore works, on a character the person names (`CHAR`, such as `PLAYER01/char1.bic`)
whose player is logged out:

```sh
ssh $DEPLOY_USER@$GAME "sudo nwn-vault-history log $CHAR | head -3"
```

Success: one or more lines, newest first. Restore only when the person asks for it, with the version or time they
give (`WHEN`):

```sh
ssh $DEPLOY_USER@$GAME "sudo nwn-vault-history restore $CHAR '$WHEN'"
```

Success: `restored ... as it was in <commit>`, and the path of the replaced file. Tell the person both.

Within 35 minutes of step 3, the timer has run on its own:

```sh
ssh $DEPLOY_USER@$GAME 'systemctl show vault-history.service -p Result --value; cat game/vault-history.ok'
```

Success: `success`, and a time after step 3's.

## Roll back

```sh
ssh $DEPLOY_USER@$GAME 'sudo systemctl disable --now vault-history.timer; sudo rm -f /etc/systemd/system/vault-history.{service,timer} /usr/local/sbin/nwn-vault-history; sudo systemctl daemon-reload; echo removed'
```

Success: `removed`. This stops the history; the folder `game/vault-history`, `vault-history.ok`,
`vault-history.replaced` and the key stay, and so does the repository. The watchdog then alerts within 2 hours that
the history stopped: take `vault_hours` out of `watchdog.conf` and remove `game/vault-history` only when the
person says so. The watchdog's and backup script's new versions are compatible with tier 2 and stay.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- making the repository, adding or removing its deploy key, or changing its ruleset;
- a fingerprint for the git host that isn't the one the person confirmed;
- any `restore`: the person names the character and the time, and confirms the player is logged out;
- removing `game/vault-history`, `vault-history.replaced`, the key, or anything in the repository;
- rewriting the history (`git filter-repo`, force-push), even when a player asks for their characters to be
  removed: that is the person's to do;
- cloning, copying or printing the vault's contents anywhere.
