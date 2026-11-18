# Playbook 16. A release (tier 1)

For an agent. The chapter for people is [`chapters/16-releasing.md`](../chapters/16-releasing.md). Follow the steps
in order. Do not go on from a step whose check fails.

A release disconnects players. You do every check and prepare every file. **A person says yes before step 5,
every time.** An earlier or general go-ahead does not count.

`GUIDE` below is the root of this repository on the person's computer.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `GUIDE` | Where this repository is | none: a person gives it |
| `REPO_DIR` | The module's repository | `~/mymodule` |
| `HAKS_DIR` | The content repository, if content changed in this release | empty |
| `GH_REPO` | The module's GitHub repository, as `owner/name` | none: a person gives it |
| `VERSION` | The tag for this release, such as `v0.2` | none: a person gives it |
| `SERVER` | The server's address or name | none: a person gives it |
| `DEPLOY_USER` | The account made in playbook 1 | `nwn` |

Secrets: none pass through you. The plugin check reads only lines of the form `NWNX_<NAME>_SKIP=` from the
server's `.env`. Never read the rest of that file.

## Preconditions

```sh
ssh $DEPLOY_USER@$SERVER 'cd game && ls release.sh backup.sh >/dev/null && echo "scripts ok"; docker compose ps --format "{{.Service}} {{.Health}}" | grep -c healthy'
ls "$REPO_DIR/tools/check_plugins.py" >/dev/null && echo "check ok"
```

Success: `scripts ok`, `2` or more, `check ok`. Missing files are copied as the chapter's opening shows.

## Steps

### 1. The check on `main` is green

```sh
gh run list -R $GH_REPO --branch main --limit 1 --json status,conclusion,headSha -q '.[0] | "\(.status) \(.conclusion) \(.headSha[0:7])"'
git -C "$REPO_DIR" fetch -q origin && git -C "$REPO_DIR" rev-parse --short=7 origin/main
```

Success: `completed success` and a commit, and the second line is the same commit. If the newest commit on `main`
has no finished, successful run, stop: there is nothing to release yet.

### 2. The plugin check

```sh
[ "$(git -C "$REPO_DIR" rev-parse HEAD)" = "$(git -C "$REPO_DIR" rev-parse origin/main)" ] && echo "working copy is at main"; ssh $DEPLOY_USER@$SERVER 'grep -E "^NWNX_[A-Z0-9_]+_SKIP=" game/.env' | python3 "$REPO_DIR/tools/check_plugins.py" "$REPO_DIR/src" -
```

Success: `working copy is at main`, then `the server has every plugin the module uses switched on`, exit status 0. If the working copy is somewhere else, ask the person to switch it to `main`; do not change their checkout yourself. If it lists a plugin, report it
and stop: switching a plugin on is a settings change the person decides.

### 3. One NWNX version

```sh
ssh $DEPLOY_USER@$SERVER 'grep "^NWNX_IMAGE=" game/.env | cut -d= -f2'; grep "NWNX_IMAGE:" "$REPO_DIR/.github/workflows/compile-check.yml" | awk '{print $2}'
```

Success: the same image and tag twice.

### 4. Prepare the files

```sh
RUN=$(gh run list -R $GH_REPO --branch main --limit 1 --json databaseId -q '.[0].databaseId'); rm -rf /tmp/release && gh run download $RUN -R $GH_REPO -n module -D /tmp/release && ssh $DEPLOY_USER@$SERVER 'mkdir -p ~/incoming' && scp /tmp/release/*.mod $DEPLOY_USER@$SERVER:incoming/
```

If `HAKS_DIR` is set, publish the content first and then send the files: the "Later updates" part of playbook 7,
steps 1 and 2, and then:

```sh
scp "$HAKS_DIR"/build/hak/*.hak "$HAKS_DIR"/build/tlk/*.tlk $DEPLOY_USER@$SERVER:incoming/
```

Success: exit status 0, and `ssh $DEPLOY_USER@$SERVER 'ls ~/incoming'` lists the files.

### 5. Release

**Ask first.** Tell the person what is in `~/incoming`, that players will be disconnected for a few seconds, and
wait for a yes.

```sh
ssh $DEPLOY_USER@$SERVER 'cd game && sudo ./release.sh'
```

Success: the last line is `the game is healthy again`, exit status 0. If it ends with
`the game did not become healthy`, run the Roll back command at once and then report.

### 6. Tag

```sh
git -C "$REPO_DIR" tag -a $VERSION -m "Release $VERSION" origin/main && git -C "$REPO_DIR" push -q origin $VERSION
```

Success: exit status 0. Tag the content repository the same way if it changed.

## Verify

```sh
"$GUIDE/templates/game/nwn-status.py" $SERVER
ssh $DEPLOY_USER@$SERVER 'cd game && docker compose logs --since 5m nwserver | grep -c "Module loaded"; ls -1 releases | tail -1; ls -1 backups | tail -1'
```

Success: the game answers; `1` or more; the newest folder in `releases` and the newest backup both carry the time
of this release.

The person does the last check: they join and try what the release is about.

## Roll back

```sh
ssh $DEPLOY_USER@$SERVER 'cd game && sudo ./release.sh --undo'
```

Success: `the game is healthy again`. This puts back the files the release replaced. It does not change the
database back. If the release changed stored data, tell the person: restoring the database is their decision, from
the backup that `release.sh` made (chapter 12).

## Stop and ask

Hand back to a person, with what you found, before any of these:

- step 5, always;
- any change to the server's `.env`, including switching a plugin on;
- `docker compose up -d` on the server: it restarts the game;
- restoring a database;
- a release when the check on `main` is not green, or when the plugin check fails;
- deleting anything in `releases`, `backups` or `~/incoming/done`.
