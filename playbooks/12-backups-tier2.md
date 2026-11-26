# Playbook 12, tier 2. Off-site encrypted backups with borg

For an agent. The chapter for people is [`chapters/12-backups.md`](../chapters/12-backups.md), section "Tier 2".
Follow the steps in order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer. Run steps 1 to 6 once for each
machine: first with `ROLE=game` on the game host, then with `ROLE=control` on the control host.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `HOST` | The machine being backed up: its public address | none: a person gives it |
| `ROLE` | `game` or `control`: which config and hook the machine gets | none |
| `NAME` | Names the machine's repository, key and archives | `$ROLE` |
| `DEPLOY_USER` | The deploy user on `HOST` | `nwn` |
| `STORAGE` | The storage machine's address | none: a person gives it |
| `STORAGE_ADMIN` | How to reach the storage machine with `sudo`, if it is one of the person's own machines, such as `nwn@STORAGE`. Empty for a storage box: then a person adds the `authorized_keys` lines | empty |
| `REPO_BASE` | The repositories' folder on the storage side | `/home/borg/repos` |
| `QUOTA` | The storage quota per repository | `20G` |

Secrets: each machine's passphrase is made on that machine by step 2 and never leaves it through the agent. Never
print `/etc/nwn-borg/passphrase`, `/etc/nwn-borg/ssh-key`, a `borg key export`, `/data/coolify/source/.env` or
`/etc/nwn-borg/alert-webhook`. Step 4 hands the passphrase and key to the person, by commands the person runs.
Public keys and fingerprints are not secret.

## Preconditions

Playbook 12 (tier 1) is done on the game host, and this machine has no borg setup yet:

```sh
ssh $DEPLOY_USER@$HOST 'sudo test -e /etc/nwn-borg && echo "has nwn-borg" || echo "no nwn-borg"; systemctl is-active nwn-backup.timer 2>/dev/null; docker ps --format "{{.Names}}" | grep -c -E "mariadb|coolify-db"'
```

Success on the game host: `no nwn-borg`, `active`, `1` or more. On the control host the middle line may be
`inactive`. If `has nwn-borg`, stop and ask.

The storage side has an account `borg` with `$REPO_BASE` (chapter, step 9). With `STORAGE_ADMIN` set:

```sh
ssh $STORAGE_ADMIN "sudo -u borg test -d $REPO_BASE && sudo -u borg test -f /home/borg/.ssh/authorized_keys && echo ready; sudo -u borg test -e $REPO_BASE/$NAME && echo 'repository exists' || true"
```

Success: `ready`, and no `repository exists`. If it exists, stop and ask.

## Steps

### 1. Install borg and the script

```sh
scp -r templates/backup $DEPLOY_USER@$HOST:backup
ssh $DEPLOY_USER@$HOST "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq borgbackup >/dev/null && cd backup && sudo install -m 755 borg-backup.sh /usr/local/sbin/nwn-borg-backup && sudo install -d -m 700 /etc/nwn-borg /etc/nwn-borg/hooks.d && if [ $ROLE = game ]; then sudo install -m 700 hooks/10-game-db.sh /etc/nwn-borg/hooks.d/ && sudo install -m 600 borg.conf.example /etc/nwn-borg/borg.conf; else sudo install -m 700 hooks/10-coolify-db.sh /etc/nwn-borg/hooks.d/ && sudo install -m 600 borg.conf.control.example /etc/nwn-borg/borg.conf; fi && sudo sed -i 's|STORAGE|$STORAGE|; s|/repos/[a-z]*\$|/repos/$NAME|; s|^NAME=.*|NAME=$NAME|; s|/home/nwn/|/home/$DEPLOY_USER/|g' /etc/nwn-borg/borg.conf && sudo grep -E '^(NAME|REPO)=' /etc/nwn-borg/borg.conf && borg --version"
```

Success: `NAME=$NAME`, `REPO=ssh://borg@$STORAGE/./repos/$NAME`, then `borg 1.4` or later. For a storage box, also set `REPO` (port 23, its account name) and
`BORG_REMOTE_PATH` in `/etc/nwn-borg/borg.conf` as the person tells you.

### 2. The key, the passphrase, the storage's fingerprint

```sh
ssh $DEPLOY_USER@$HOST "sudo ssh-keygen -q -t ed25519 -N '' -C borg-$NAME -f /etc/nwn-borg/ssh-key && sudo sh -c 'umask 077; openssl rand -base64 32 > /etc/nwn-borg/passphrase' && sudo sh -c 'ssh-keyscan -t ed25519 $STORAGE > /etc/nwn-borg/known_hosts 2>/dev/null' && sudo ssh-keygen -lf /etc/nwn-borg/known_hosts && sudo stat -c '%a %n' /etc/nwn-borg/passphrase /etc/nwn-borg/ssh-key"
```

Success: one fingerprint line, then `600` twice. With `STORAGE_ADMIN` set, compare the fingerprint with
`ssh $STORAGE_ADMIN 'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub'`; they must be the same. For a storage box,
show it to the person and ask them to compare.

### 3. Lock the key on the storage side

```sh
K=$(ssh $DEPLOY_USER@$HOST 'sudo cat /etc/nwn-borg/ssh-key.pub')
LINE="command=\"borg serve --append-only --restrict-to-repository $REPO_BASE/$NAME --storage-quota $QUOTA\",restrict $K"
echo "$LINE" | ssh $STORAGE_ADMIN 'sudo -u borg tee -a /home/borg/.ssh/authorized_keys > /dev/null'
ssh $STORAGE_ADMIN "sudo grep -c 'append-only --restrict-to-repository $REPO_BASE/$NAME ' /home/borg/.ssh/authorized_keys"
```

Success: `1`. For a storage box, print `$LINE` (it holds only a public key) and ask the person to add it, then go on.

### 4. Make the repository; the person saves the passphrase and key

```sh
ssh $DEPLOY_USER@$HOST 'sudo nwn-borg-backup borg init --encryption=repokey-blake2 > /dev/null 2>&1; echo "init $?"; sudo nwn-borg-backup borg info | grep -c "Repository ID"'
```

Success: `init 0`, `1`.

**Stop and ask** now. Tell the person, word for word: "Please run these two commands yourself and put both
outputs into one entry in your password manager. Without the passphrase these backups can never be read." The
commands, for them to run:

```sh
ssh -t DEPLOY_USER@HOST 'sudo cat /etc/nwn-borg/passphrase'
ssh -t DEPLOY_USER@HOST 'sudo nwn-borg-backup borg key export'
```

On the control host, add: "and the `APP_KEY=` line from `sudo grep ^APP_KEY= /data/coolify/source/.env`". Wait
until the person says they have saved them. Do not go on before.

### 5. The first and second backup

```sh
ssh $DEPLOY_USER@$HOST 'sudo nwn-borg-backup 2>&1 | grep -E "^This archive|backup made"; sudo nwn-borg-backup 2>&1 | grep -E "^This archive|backup made"; sudo nwn-borg-backup borg list --short | wc -l'
```

Success: two `backup made: $NAME-...` lines; the second `This archive` line's last number much smaller than the
first's; then `2`.

### 6. The nightly timer

```sh
ssh $DEPLOY_USER@$HOST 'cd backup && sudo cp borg-backup.service borg-backup.timer /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now borg-backup.timer 2>/dev/null; systemctl is-active borg-backup.timer; systemctl show borg-backup.timer -p NextElapseUSecRealtime --value; sudo systemctl start borg-backup.service; systemctl show borg-backup.service -p Result --value'
```

Success: `active`, a time in the hour 09 UTC, `success`.

If the person gives a webhook address for alerts, they put it in place themselves
(`sudo sh -c 'umask 077; cat > /etc/nwn-borg/alert-webhook'`), then you check it:
`ssh $DEPLOY_USER@$HOST 'sudo nwn-borg-backup --test-alert'`. Success: `sent`, and the person sees the message.

## Verify

After steps 1 to 6 have run for every machine. The lock holds: from the game host, deleting the repository is
refused, and another repository is out of reach:

```sh
ssh $DEPLOY_USER@$HOST 'sudo nwn-borg-backup borg delete --force 2>&1 | grep -q "append-only mode" && echo refused; sudo BORG_PASSCOMMAND="cat /etc/nwn-borg/passphrase" BORG_RSH="ssh -i /etc/nwn-borg/ssh-key -o UserKnownHostsFile=/etc/nwn-borg/known_hosts -o BatchMode=yes" borg list ssh://borg@'$STORAGE'/./repos/somewhere-else 2>&1 | grep -q "not allowed" && echo "out of reach"'
```

Success: `refused`, `out of reach`. (For a storage box, the path in the second command follows its `REPO` form.)

A restore into a side folder, compared with the live files, nothing live touched:

```sh
ssh $DEPLOY_USER@$HOST sudo bash -s <<'EOF'
a=$(nwn-borg-backup borg list --short --last 1); d=$(mktemp -d); cd "$d" || exit 1
nwn-borg-backup borg extract "::$a" || exit 1
n=0; for f in $(find . -type f ! -path "./var/backups/*"); do n=$((n+1)); cmp -s "$f" "/${f#./}" || echo "DIFFERENT: $f"; done
echo "compared $n files"; cd / && rm -rf "$d"
EOF
```

Success: `compared` and a number above 0, with no `DIFFERENT` line. A file changed since the backup (a character saved a moment ago)
may differ; run a fresh backup and compare again before you report it.

The tidy, as a look only, from the person's computer, if they have set up their key (chapter, step 17). The person
types the passphrase:

```sh
templates/backup/borg-prune.sh ssh://borg@$STORAGE/./repos/$NAME
```

Success: the archive count, `newest: ... 0 hours old`, and `nothing removed`.

## Roll back

- **Stop the nightly backup:** `sudo systemctl disable --now borg-backup.timer` on the machine. Its archives stay.
- **Take a machine's access away:** remove its line from `authorized_keys` on the storage side. Ask first.
- Removing a repository, or anything in it, is never part of a roll back. Ask the person.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- step 4's passphrase and key, always: the person saves them, the agent never sees them;
- `borg-prune.sh ... --apply`, `borg compact` or `borg delete` with a key that may delete;
- `borg-prune.sh` saying `STOP` or `REFUSING`; never work around it, never run a tidy after it;
- winding back a repository (`borg-wind-back.sh ... --apply`), and removing its `.before-` copy;
- extracting over live data: `borg extract` from `/` on a machine whose game is running. The chapter's step 19
  is for a new, empty machine;
- adding or removing any line in `authorized_keys` on a storage box, or removing a machine's line anywhere;
- a key line without `--append-only` for anything but the person's own tidy key;
- a backup that fails twice: report the last lines of `journalctl -u borg-backup.service`.
