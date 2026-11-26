# Playbook 6, tier 2. Tests on a real server, a staging copy, releases by tag

For an agent. The chapter for people is [`chapters/06-module.md`](../chapters/06-module.md), section "Tier 2".
Follow the steps in order. Do not go on from a step whose check fails.

`GUIDE` is the root of this repository on the person's computer. Run every command in `REPO_DIR` unless it says
otherwise.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `GUIDE` | Where this repository is | none: a person gives it |
| `REPO_DIR` | The module's repository from playbook 6 | `~/mymodule` |
| `GH_REPO` | Its GitHub repository, `owner/name` | none: a person gives it |
| `MODULE_NAME` | The module's name, as in `nasher.cfg` and the live `NWN_MODULE` | `mymodule` |
| `GAME` | The game host's public address | none: a person gives it |
| `DEPLOY_USER` | The deploy user | `nwn` |
| `STAGING_PORT` | The staging game's UDP port | `5122` |
| `VERSION` | The tag to release, `vX.Y.Z` | none: a person gives it |
| `NWSYNC_URL` | The download address players' games use (chapter 7), if the module lists haks | empty: no haks |

Secrets: the staging game's passwords are typed by a person into Coolify (step 5). The staging key is made by you
in step 6 in a private temporary file and goes only to GitHub (`gh secret set` reads it from standard input) and
then is deleted; never print it. GitHub access is the person's own `gh` login.

## Preconditions

```sh
nasher --version | head -1; ls "$NWN_ROOT/data/nwn_base.key" > /dev/null && echo "game ok"; docker compose version --short
git -C "$REPO_DIR" status -s | wc -l; ls "$REPO_DIR/tests/run.sh" 2>/dev/null | wc -l
gh run list -R $GH_REPO -w "Compile check" -b main -L 1 --json conclusion -q '.[0].conclusion'
ssh $DEPLOY_USER@$GAME 'ls -d game/backups/*/ | tail -1; docker ps --format "{{.Label \"com.docker.compose.service\"}}" | sort | tr "\n" " "'
[ -z "$NWSYNC_URL" ] || { V=$(curl -fsS "$NWSYNC_URL/latest"); echo $V; curl -fsS -o /dev/null -w '%{http_code}\n' "$NWSYNC_URL/manifests/$V.origin"; }
```

Success: `nasher 1.2.2`, `game ok`, a Compose version; `0` and `0` (clean, no tests yet; if `1`, the tests are
already there: skip step 1); `success`; a backup folder; the services include `mariadb nwserver` and no
`staging-nwserver`. If a staging service exists, stop and ask. With `NWSYNC_URL`: a 40-character version, then
`200`. A `404` there means the content was written without `--write-origins`: a person publishes it once more with
chapter 7's command or `publish.sh` (same content, same version), then start again.

## Steps

### 1. Copy the tests in

```sh
cp -r "$GUIDE/templates/module/tests" . && mkdir -p .github/actions && cp -r "$GUIDE/templates/module/.github/actions/nwn-tools" .github/actions/ && cp "$GUIDE/templates/module/.github/workflows/tests.yml" "$GUIDE/templates/module/.github/workflows/release.yml" .github/workflows/ && printf 'tests/.run/\ntests/.content/\n' >> .gitignore
grep -q '^name = "test"' nasher.cfg || printf '\n[target]\nname = "test"\ndescription = "The module plus the tests in tests/nss, for tests/run.sh. Never put this one on a server."\nfile = "test.mod"\n\n  [target.sources]\n  include = "src/**/*.{nss,json}"\n  include = "tests/nss/*.nss"\n' >> nasher.cfg
grep -h 'NWNX_IMAGE:' .github/workflows/*.yml | sort -u
[ -z "$NWSYNC_URL" ] || sed -i "s|^  NWSYNC_URL: .*|  NWSYNC_URL: \"$NWSYNC_URL\"|" .github/workflows/tests.yml; grep '^  NWSYNC_URL:' .github/workflows/tests.yml
```

Success: one `NWNX_IMAGE:` line (all three workflows name the same image). If there are two, set the tests' and
the release's to the compile check's. Then the `NWSYNC_URL:` line, with the address or empty.

### 2. Run the tests

```sh
tests/run.sh ${NWSYNC_URL:+--content "$NWSYNC_URL"} > /tmp/tests-out.txt; echo "exit $?"; tail -6 /tmp/tests-out.txt
```

Success: `exit 0`, then lines starting `PASS` and a last line `N passed, 0 failed, ...`. (The exit status is
taken before any pipe on purpose: `run.sh | tail` would report `tail`'s.) A `SKIP t_load_recorded` is
fine in a module without chapter 6's `mod_load`. With `NWSYNC_URL`, `grep ^content /tmp/tests-out.txt` shows `content <version>: N files
checked, ...`. `the module needs X.hak` means the module lists content that isn't published or staged: stop and ask
(a person stages it with chapter 7's `publish.sh`). On a failure read `tests/.run/logs/nwserverLog1.txt` and
`nwengineLog.txt`, and stop and ask: do not change or delete a test to make it pass.

### 3. Prove a test can fail

```sh
printf '#include "inc_test"\nvoid main()\n{\n    AssertInt(2 + 2, 5, "arithmetic");\n}\n' > tests/nss/t_zz_wrong.nss; tests/run.sh --filter t_zz_ | tail -2; rm tests/nss/t_zz_wrong.nss
```

Success: `FAIL  t_zz_wrong  (arithmetic: got 4, want 5; ...)` and `0 passed, 1 failed, 0 skipped`.

### 4. Push on a branch, and see the workflow run

```sh
git checkout -b tests && git add -A && git commit -q -m "Tests on a real server" && git push -q -u origin tests && gh pr create -R $GH_REPO --fill | tail -1
sleep 15; RUN=$(gh run list -R $GH_REPO -w Tests -b tests -L 1 --json databaseId -q '.[0].databaseId'); gh run watch $RUN -R $GH_REPO --exit-status > /dev/null; echo "exit $?"
```

Success: a pull request URL, `exit 0`. A person merges it.

### 5. The staging service

**Ask first.** Tell the person a second game will run on the game host, on UDP `STAGING_PORT`, and wait for a yes.

```sh
ssh $DEPLOY_USER@$GAME 'mkdir -p ~/staging/home/modules ~/staging/db ~/staging/logs' && scp "$GUIDE/templates/game/stage.sh" $DEPLOY_USER@$GAME:staging/
```

Then a person, in Coolify (chapter 6, step 18): adds `templates/game/staging.yaml` as a Docker Compose service on
the game host (with `/home/nwn` changed if `DEPLOY_USER` isn't `nwn`), types its settings with new passwords and
`NWN_MODULE=$MODULE_NAME`, deploys it, and opens UDP `STAGING_PORT` in the provider's firewall. Then:

```sh
ssh $DEPLOY_USER@$GAME 'docker ps --format "{{.Label \"com.docker.compose.service\"}}" | sort | tr "\n" " "'
```

Success: `mariadb nwserver staging-mariadb staging-nwserver` (perhaps with others). Never with two `nwserver`.

### 6. The first stage, the key, and the environment

**Ask first** before adding a key to the game host.

```sh
gh run download -R $GH_REPO $(gh run list -R $GH_REPO -w "Compile check" -b main -L 1 --json databaseId -q '.[0].databaseId') -n module -D /tmp/stage-first && ssh $DEPLOY_USER@$GAME 'sudo staging/stage.sh "stage v0.0.1"' < /tmp/stage-first/$MODULE_NAME.mod | tail -1
umask 077; K=$(mktemp -d)/k; ssh-keygen -q -t ed25519 -N '' -C staging-from-github -f $K
{ printf 'command="sudo -n /home/%s/staging/stage.sh \\"$SSH_ORIGINAL_COMMAND\\"",restrict ' $DEPLOY_USER; cat $K.pub; } | ssh $DEPLOY_USER@$GAME 'cat >> ~/.ssh/authorized_keys'
ssh -i $K -o IdentitiesOnly=yes $DEPLOY_USER@$GAME "stage v0.0.2" < /tmp/stage-first/$MODULE_NAME.mod | tail -1; ssh -i $K -o IdentitiesOnly=yes $DEPLOY_USER@$GAME 'id' 2>&1 | tail -1
```

Success: `staging is healthy with v0.0.1`, then `staging is healthy with v0.0.2`, then `usage: stage vX.Y.Z  (got: id)`.

```sh
gh api -X PUT repos/$GH_REPO/environments/staging --input - <<< '{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}' > /dev/null
gh api -X POST repos/$GH_REPO/environments/staging/deployment-branch-policies -f name='v*' -f type=tag -q .name
gh secret set STAGING_SSH_KEY -R $GH_REPO --env staging < $K && rm -rf "$(dirname $K)"
gh variable set STAGING_HOST -R $GH_REPO --env staging --body "$GAME"
ssh-keyscan -t ed25519 $GAME 2>/dev/null | gh variable set STAGING_KNOWN_HOSTS -R $GH_REPO --env staging
gh secret list -R $GH_REPO --env staging | cut -f1; gh variable list -R $GH_REPO --env staging | cut -f1
```

Success: `v*`, then `STAGING_SSH_KEY`, `STAGING_HOST` and `STAGING_KNOWN_HOSTS` listed. Before the last line, compare `ssh-keyscan`'s key with the
person's own `~/.ssh/known_hosts` entry for `GAME` (`ssh-keygen -F $GAME`); if they differ, stop and ask.

### 7. Release by tag

**Ask first.** Tell the person the version and the commit (`git log -1 --oneline origin/main`), and wait for a yes.

```sh
git checkout -q main && git pull -q && git tag -a $VERSION -m "$VERSION" && git push -q origin $VERSION
sleep 15; RUN=$(gh run list -R $GH_REPO -w Release -L 1 --json databaseId -q '.[0].databaseId'); gh run watch $RUN -R $GH_REPO --exit-status > /dev/null; echo "exit $?"
gh run view $RUN -R $GH_REPO --log | grep -o 'staging is healthy with .*' | tail -1
```

Success: `exit 0` and `staging is healthy with $VERSION`. On a failure, `gh run view $RUN -R $GH_REPO --log-failed`
and stop and ask.

## Verify

```sh
"$GUIDE/templates/game/nwn-status.py" $GAME $STAGING_PORT
gh release view $VERSION -R $GH_REPO --json assets -q '.assets[].name' | tr '\n' ' '; echo
gh release download $VERSION -R $GH_REPO -p SHA256SUMS -O - | cut -d' ' -f1; ssh $DEPLOY_USER@$GAME 'cat staging/staged.txt'
ssh $DEPLOY_USER@$GAME 'cd game && sudo ./backup.sh | tail -1'
```

Success: `... is up: module $MODULE_NAME ...`; `$MODULE_NAME.mod SHA256SUMS`; the checksum from the release is
the one in `staged.txt`; a new live backup (the live game is still found with staging running).

Going live is the person's own step (chapter 6, step 22). Do not run it.

## Roll back

- **Staging:** stop or delete the staging service in Coolify; delete the key's line from
  `~/.ssh/authorized_keys` on the game host (it ends in `staging-from-github`); delete the `staging` environment
  in the repository's settings. `~/staging` can stay or go; nothing live reads it.
- **A release:** a tag and a release can be deleted by a person (`gh release delete`, `git push --delete origin`).
  Never reuse a version number that has been on staging; tag the next one.
- **The tests:** revert the pull request from step 4.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- step 5, step 6's key, and every tag (step 7);
- going live, always; this playbook never runs `release.sh`;
- a test that fails and that you would want to change, skip or delete;
- a staging service named `nwserver` or `mariadb`, or a second of either;
- a host key from `ssh-keyscan` that doesn't match the person's own record;
- printing, copying anywhere else, or keeping the staging key after step 6.
