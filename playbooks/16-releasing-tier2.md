# Playbook 16, tier 2. A staged release, checked

For an agent. The chapter for people is [`chapters/16-releasing.md`](../chapters/16-releasing.md), section "Tier
2". Follow the steps in order. Do not go on from a step whose check fails.

You prepare and check a release up to `preflight.sh`. **A person says yes before step 6, every time.** An earlier
or general go-ahead does not count. The fallbacks and the ways back at the end are theirs to choose; you may run
them only after their yes for that one command.

`GUIDE` is the root of this repository on the person's computer.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `GUIDE` | Where this repository is | none: a person gives it |
| `REPO_DIR` | The module's repository | `~/mymodule` |
| `GH_REPO` | Its GitHub repository, `owner/name` | none: a person gives it |
| `MODULE_NAME` | The module's name, the live `NWN_MODULE` | `mymodule` |
| `VERSION` | The tag for this release, `vX.Y.Z` | none: a person gives it |
| `CONTENT` | `yes` if this release changes haks or the talk table | none: a person says |
| `GAME` | The game host's public address | none: a person gives it |
| `CONTROL` | The control host's public address | none: a person gives it |
| `DEPLOY_USER` | The deploy user on both machines | `nwn` |
| `STAGING_PORT` | The staging game's UDP port | `5122` |

Secrets: none pass through you. `preflight.sh` reads only container health, file checksums, the migrations ledger,
backup dates and the download address. Never print `~/game/.env` or a Coolify service's settings.

## Preconditions

```sh
ssh $DEPLOY_USER@$GAME 'cd game && ls preflight.sh release.sh migrate.sh restore-db.sh ../staging/stage.sh > /dev/null && echo "game scripts ok"; docker ps --format "{{.Label \"com.docker.compose.service\"}}" | sort | tr "\n" " "; echo'
ssh $DEPLOY_USER@$CONTROL 'ls content/publish.sh content/promote.sh > /dev/null && grep -c "STAGING_DIR" content/lib.sh'
gh run list -R $GH_REPO -b main -L 2 --json workflowName,conclusion,headSha -q '.[] | "\(.workflowName) \(.conclusion) \(.headSha[0:7])"'
git -C "$REPO_DIR" fetch -q origin && git -C "$REPO_DIR" rev-parse --short=7 origin/main
```

Success: `game scripts ok`; the services include `mariadb nwserver staging-mariadb staging-nwserver` (never two
`nwserver`); a number of `1` or more (the control host has this chapter's `publish.sh`); `Compile check success`
and `Tests success`, both on the commit the last line prints. If a script is missing, copy it as the chapter's
opening shows. If `main` is not green, stop: there is nothing to release yet.

## Steps

### 1. The plugin check and one NWNX version

```sh
ssh $DEPLOY_USER@$GAME 'grep -E "^NWNX_[A-Z0-9_]+_SKIP=" game/.env' | python3 "$REPO_DIR/tools/check_plugins.py" "$REPO_DIR/src" -
ssh $DEPLOY_USER@$GAME 'grep "^NWNX_IMAGE=" game/.env | cut -d= -f2'; grep -h "NWNX_IMAGE:" "$REPO_DIR"/.github/workflows/*.yml | awk '{print $2}' | sort -u
```

Success: `the server has every plugin the module uses switched on`, then the same image twice (one line from the
workflows). Otherwise report and stop: a plugin switch is a settings change the person decides.

### 2. Content, if `CONTENT` is `yes`

```sh
RUN=$(gh run list -R $GH_REPO -w "Compile check" -b main -L 1 --json databaseId -q '.[0].databaseId'); rm -rf /tmp/publish-mod && gh run download $RUN -R $GH_REPO -n module -D /tmp/publish-mod && scp -q /tmp/publish-mod/$MODULE_NAME.mod $DEPLOY_USER@$CONTROL:$MODULE_NAME.mod
ssh $DEPLOY_USER@$CONTROL "~/content/publish.sh ~/$MODULE_NAME.mod" | tail -4
```

Success: `staging has the same content; it hands it out from its next stage`, `staged <40 characters>`, and
`players still get ...`. If the staging line is missing, the game host has no `~/staging`: report it. Skip this
step if `CONTENT` is not `yes`.

### 3. Tag, and see it staged

**Ask first.** Tell the person the version and the commit (`git -C "$REPO_DIR" log -1 --oneline origin/main`), and
wait for a yes.

```sh
git -C "$REPO_DIR" tag -a $VERSION -m "$VERSION" origin/main && git -C "$REPO_DIR" push -q origin $VERSION
sleep 15; RUN=$(gh run list -R $GH_REPO -w Release -L 1 --json databaseId -q '.[0].databaseId'); gh run watch $RUN -R $GH_REPO --exit-status > /dev/null; echo "exit $?"
gh run view $RUN -R $GH_REPO --log | grep -o 'staging is healthy with .*' | tail -1
gh release download $VERSION -R $GH_REPO -p SHA256SUMS -O - | cut -d' ' -f1; ssh $DEPLOY_USER@$GAME 'cat staging/staged.txt'
```

Success: `exit 0`, `staging is healthy with $VERSION`, and the checksum on the third line appears in `staged.txt`.
If the staging job failed, read why and report, then stop:

```sh
ssh $DEPLOY_USER@$GAME 'docker logs --tail 30 $(docker ps -q --filter label=com.docker.compose.service=staging-nwserver) 2>&1 | grep -a -v "^\s*$" | tail -8; sudo grep -a -i -E "couldn.t|error" staging/logs/nwengineLog.txt | tail -5'
```

A missing hak there means content that was not published: the person decides whether to publish it (step 2) and
re-run the failed job (`gh run rerun $RUN -R $GH_REPO --failed`).

### 4. The person tries staging

```sh
"$GUIDE/templates/game/nwn-status.py" $GAME $STAGING_PORT
```

Success: `... is up: module $MODULE_NAME ...`. Then tell the person staging is ready to try, on `GAME` port
`STAGING_PORT`, and wait until they say they have.

### 5. Into `~/incoming`, and the pre-flight

```sh
ssh $DEPLOY_USER@$GAME "mkdir -p ~/incoming && sudo cp ~/staging/home/modules/$MODULE_NAME.mod ~/incoming/ && rm -rf ~/incoming/migrations"
git -C "$REPO_DIR" worktree add -q /tmp/release-$VERSION $VERSION && { [ -d /tmp/release-$VERSION/migrations ] && scp -q -r /tmp/release-$VERSION/migrations $DEPLOY_USER@$GAME:incoming/; git -C "$REPO_DIR" worktree remove /tmp/release-$VERSION; }
ssh $DEPLOY_USER@$GAME 'cd game && sudo ./preflight.sh'; echo "exit $?"
```

Success: every line `ok` or `--`, the last `nothing to look at: ready when you are`, `exit 0`, and the line
`$MODULE_NAME.mod waits, the same file staging runs ($VERSION)`. With `CONTENT=yes`, a `waits` line for each hak
and talk table too. Any `LOOK`: report the lines and stop. Do not fix a `LOOK` by changing files on the server.

### 6. Go live

**Ask first.** Tell the person what `preflight.sh` listed as waiting, that players are disconnected for a few
seconds, and wait for a yes.

`CONTENT=yes`:

```sh
ssh $DEPLOY_USER@$CONTROL '~/content/promote.sh'; echo "exit $?"
```

Otherwise:

```sh
ssh $DEPLOY_USER@$GAME 'cd game && sudo ./release.sh'; echo "exit $?"
```

Success: `the game is healthy again`, after a promote also `the game hands out <the staged version>`, and `exit
0`. On anything else, report the last ten lines exactly, and stop: the way back is the person's choice (Roll back).

## Verify

```sh
"$GUIDE/templates/game/nwn-status.py" $GAME
ssh $DEPLOY_USER@$GAME 'cd game && sudo ./preflight.sh | grep -v -E "^ok|^--"; ./migrate.sh status | head -1; ls -1 releases | tail -1'
```

Success: the game answers; the only `LOOK` is `nothing in .../incoming to release`; no migration waiting; the
newest folder in `releases` has the time of this release. The person joins and tries what the release is about.

## Roll back

Each is the person's choice, after their yes for that command:

| They choose | Command | Success |
|---|---|---|
| The files back, after a promote | `ssh $DEPLOY_USER@$CONTROL '~/content/promote.sh --back'` | `the game hands out <the version before>` |
| The files back, after `release.sh` | `ssh $DEPLOY_USER@$GAME 'cd game && sudo ./release.sh --undo'` | `the game is healthy again` |
| The database back | `ssh -t $DEPLOY_USER@$GAME 'cd game && sudo ./restore-db.sh backups/<the backup-before named by the undo>'` | `database restored from ...`; the person types `restore` themselves |

The tag and the GitHub release stay: they record what was tried. Undoing a release does not undo its migrations;
the undo says which ran and which backup came before.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- step 3 (a tag), step 6 (going live), and any rerun of a failed GitHub job;
- every command in Roll back;
- every fallback in the chapter's steps 19 to 22: a restart, `docker rm`, `docker compose up -d`, a Coolify
  deploy or restart, `NWN_NWSYNCHASH`, `PULL=no`, a hand stage;
- any change to `~/game/.env`, a Coolify setting, `~/incoming` beyond step 5, or a migration file;
- a `LOOK` from `preflight.sh`, a red run on `main`, a failed plugin check;
- deleting anything in `releases`, `backups`, `~/incoming/done`, `~/nwsync` or `~/content`.
