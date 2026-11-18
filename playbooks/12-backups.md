# Playbook 12. Nightly backups and a restore check (tier 1)

For an agent. The chapter for people is [`chapters/12-backups.md`](../chapters/12-backups.md). Follow the steps in
order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer, unless it starts with `ssh`.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `SERVER` | The server's address or name | none: a person gives it |
| `DEPLOY_USER` | The account made in playbook 1 | `nwn` |
| `BACKUP_HOUR` | The hour of the nightly backup, in UTC, two digits | `09` |
| `LOCAL_COPY` | The folder on the person's computer for the second copy | `~/nwn-backups` |

Secrets: a backup contains `.env` and `db.env`, so it contains every password of the server. Never print a file
from a backup, never unpack `files.tar.gz` anywhere but on a server it is being restored to, and never copy a
backup anywhere the person has not named.

## Preconditions

Playbook 5 is done and both containers are healthy:

```sh
ssh $DEPLOY_USER@$SERVER 'cd game && docker compose ps --format "{{.Service}} {{.Health}}" | grep -c healthy; systemctl is-enabled nwn-backup.timer >/dev/null 2>&1 && echo "a timer exists" || echo "no timer yet"'
```

Success: `2` or more, then `no timer yet`. If a timer exists, this playbook has been run here before: stop and ask.

## Steps

### 1. Copy the files

```sh
scp templates/game/backup.sh templates/game/nwn-backup.service templates/game/nwn-backup.timer $DEPLOY_USER@$SERVER:game/
```

Success: exit status 0.

### 2. Make one backup

```sh
ssh $DEPLOY_USER@$SERVER 'cd game && sudo ./backup.sh && b=$(ls -1d backups/2* | tail -1) && ls $b && zcat $b/db.sql.gz | tail -n 1 | cut -c1-17 && tar tzf $b/files.tar.gz | grep -c -E "^(\.env|db\.env|home/servervault/)$"'
```

Success: `backup made: backups/...`, the two file names `db.sql.gz` and `files.tar.gz`, `-- Dump completed`, and
`3`. The last command counts names inside the archive. It does not show any file's contents.

### 3. Install the nightly timer

```sh
ssh $DEPLOY_USER@$SERVER "cd game && sed -i 's|/home/nwn/game|/home/$DEPLOY_USER/game|g' nwn-backup.service && sed -i 's|^OnCalendar=.*|OnCalendar=*-*-* $BACKUP_HOUR:00:00|' nwn-backup.timer && sudo cp nwn-backup.service nwn-backup.timer /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now nwn-backup.timer 2>/dev/null; systemctl is-active nwn-backup.timer; systemctl show nwn-backup.timer -p NextElapseUSecRealtime --value"
```

Success: `active`, then a time on the next day (or today) in the hour `$BACKUP_HOUR` UTC.

### 4. Run the backup through the timer's service once

```sh
ssh $DEPLOY_USER@$SERVER 'sudo systemctl start nwn-backup.service; systemctl show nwn-backup.service -p Result --value; ls -1d game/backups/2* | wc -l'
```

Success: `success`, then `2` (the backup from step 2 and this one).

### 5. Fetch a second copy

Ask the person where the second copy should live if `LOCAL_COPY` was not given. Then:

```sh
mkdir -p $LOCAL_COPY && chmod 700 $LOCAL_COPY && rsync -a $DEPLOY_USER@$SERVER:game/backups/ $LOCAL_COPY/ && ls -1 $LOCAL_COPY | wc -l
```

Success: the same number as on the server. Tell the person that this copy only stays fresh if it is fetched
regularly, and that the chapter's step 4 has the line for their own computer's schedule. Setting that schedule is
theirs to do.

## Verify

Restore the newest backup into a spare database, compare, and remove the spare:

```sh
ssh $DEPLOY_USER@$SERVER 'cd game && b=$(ls -1d backups/2* | tail -1) && docker compose exec -T mariadb sh -c "mariadb -uroot -p\"\$MARIADB_ROOT_PASSWORD\" -e \"CREATE DATABASE restore_check\"" && zcat $b/db.sql.gz | docker compose exec -T mariadb sh -c "mariadb -uroot -p\"\$MARIADB_ROOT_PASSWORD\" restore_check" && docker compose exec -T mariadb sh -c "mariadb -uroot -p\"\$MARIADB_ROOT_PASSWORD\" -N -e \"SELECT (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=\\\"\$MARIADB_DATABASE\\\") = (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=\\\"restore_check\\\"); DROP DATABASE restore_check\""'
```

Success: `1`. The spare database has as many tables as the live one.

The script fails safely. This stops the database for a few seconds, so ask first if players may be on the server:

```sh
ssh $DEPLOY_USER@$SERVER 'cd game && n=$(ls -1 backups | wc -l) && docker compose stop mariadb >/dev/null 2>&1; sudo ./backup.sh >/dev/null 2>&1; echo "exit $?"; docker compose start mariadb >/dev/null 2>&1; [ "$n" = "$(ls -1 backups | wc -l)" ] && echo "no new backup"; ls -a backups | grep -c unfinished'
```

Success: `exit 1`, `no new backup`, `0`.

## Roll back

- **Stop the nightly backup:** `sudo systemctl disable --now nwn-backup.timer` on the server. Existing backups stay.
- Nothing in this playbook changes live data, so there is nothing else to undo.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- restoring over live data: loading a dump into the game's own database, or unpacking `files.tar.gz` over a `home`
  folder that is in use. The chapter's step 6 is for a new, empty machine;
- deleting any backup by hand, on the server or in the second copy;
- copying a backup to any place the person has not named;
- the second Verify check on a server that may have players on it;
- a backup that fails twice. Report the last lines of `journalctl -u nwn-backup.service`.
