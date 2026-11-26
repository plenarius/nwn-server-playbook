# Playbook 8, tier 3. Your own runners, and pictures on pull requests

For an agent. The chapter for people is [`chapters/08-ci.md`](../chapters/08-ci.md), section "Tier 3". Follow the
steps in order. Do not go on from a step whose check fails.

`GUIDE` is the root of this repository on the person's computer. Commands that start with `ssh` run on the
runners' machine; the rest run on the person's computer, in `REPO_DIR`.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `GUIDE` | Where this repository is | none: a person gives it |
| `REPO_DIR` | The module's repository | `~/mymodule` |
| `GH_REPO` | Its GitHub repository, `owner/name` | none: a person gives it |
| `MACHINE` | The runners' machine: the control host or a build machine, never the game host | none: a person gives it |
| `DEPLOY_USER` | The user you log in to `MACHINE` as, with sudo | `nwn` |
| `SLOTS`, `CPUS`, `MEMORY` | Runners, and each one's Docker's share of the machine | `3`, `1.5`, `3g` |
| `GAME_DIR` | Where the person's own copy of the game is on `MACHINE`, for pictures; empty for none | empty |

Secrets, all placed by a person, never passed through you:

- the fine-grained token (one repository, "Administration: Read and write") in `/etc/nwn-runners/token` on
  `MACHINE`, mode 600, owned by root (chapter 8, step 8). You check that the file is there; you never read it;
- for stills only, the person's second CD key in `~/.local/share/Neverwinter Nights/cdkey.ini` on `MACHINE`
  (chapter 8, step 16). The same: check it's there, never read it.

## Preconditions

```sh
ssh $DEPLOY_USER@$MACHINE 'docker version --format "{{.Server.Version}}"; nproc; free -g | awk "/Mem:/{print \$2}"; docker ps --format "{{.Names}}" | grep -c nwserver'
gh api repos/$GH_REPO -q .visibility; gh variable list -R $GH_REPO | grep -c '^CI_RUNNER'
gh run list -R $GH_REPO -w Tests -b main -L 1 --json conclusion -q '.[0].conclusion'
```

Success: a Docker version, the cores and the gigabytes (at least `SLOTS` times `CPUS` cores is not needed, but
`SLOTS` times `MEMORY` must fit with 2 GB to spare); `0` (no game server on this machine: if there is one, stop and
ask, this is the game host); `private` or `public`; `0` (no runners chosen yet); `success`.

## Steps

### 1. The runner image

```sh
scp -r "$GUIDE/templates/runner" $DEPLOY_USER@$MACHINE: && ssh $DEPLOY_USER@$MACHINE 'sudo apt-get install -y -qq jq > /dev/null && cd runner && sudo docker build -q -t nwn-runner:2.338.2 . && sudo docker run --rm --entrypoint bash nwn-runner:2.338.2 -c "gh --version | head -1; docker compose version; id -nG; echo \$ACTIONS_RUNNER_HOOK_JOB_STARTED"'
```

Success: an image ID, `gh version 2.104.0 ...`, `Docker Compose version v5.7.1`, groups without `sudo`, and
`/home/runner/hooks/job-started.sh`.

### 2. The token

A person makes the token (chapter 8, step 8) and puts it in place with the command there. Then:

```sh
ssh $DEPLOY_USER@$MACHINE 'sudo stat -c "%a %U %s" /etc/nwn-runners/token'
```

Success: `600 root` and a size over 40. Anything else: stop and ask. Never print the file.

### 3. The runners

```sh
ssh $DEPLOY_USER@$MACHINE "sudo sed -e 's|^REPO=.*|REPO=$GH_REPO|' -e 's|^SLOTS=.*|SLOTS=$SLOTS|' -e 's|^CPUS=.*|CPUS=$CPUS|' -e 's|^MEMORY=.*|MEMORY=$MEMORY|' -e 's|^GAME_DIR=.*|GAME_DIR=$GAME_DIR|' runner/runners.conf.example | sudo tee /etc/nwn-runners/runners.conf > /dev/null && sudo chmod 600 /etc/nwn-runners/runners.conf && sudo install -m 755 runner/runners.sh /usr/local/sbin/ && sudo cp runner/nwn-runners.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now nwn-runners"
sleep 60; ssh $DEPLOY_USER@$MACHINE 'sudo runners.sh status'
```

Success: `SLOTS` lines `slot N: Up ...`, then `SLOTS` runners `online busy=false nwn,self-hosted,linux,x64`. `no
registration from GitHub` in `sudo journalctl -u nwn-runners` means the token is wrong, lacks the permission, or the
machine can't reach GitHub: stop and ask.

### 4. Send the jobs there

**Ask first.** Tell the person that from now on every workflow's jobs run on `MACHINE`, and wait for a yes.

```sh
gh variable set CI_RUNNER -R $GH_REPO --body '["self-hosted","nwn"]'
gh workflow run Tests -R $GH_REPO; sleep 20; RUN=$(gh run list -R $GH_REPO -w Tests -L 1 --json databaseId -q '.[0].databaseId'); gh run watch $RUN -R $GH_REPO --exit-status > /dev/null; echo "exit $?"
gh run view $RUN -R $GH_REPO --log | grep -E 'accepted on|Runner name' | cut -f1,3 | sed 's/\t[0-9T:.-]*Z /\t/'
```

Success: `exit 0`; each job with a `Runner name` that starts with `MACHINE`'s short name, a different one for each
job, and a `job from ... accepted on ...` line. A run that stays queued for minutes: the labels don't match (step 3's
status must show `self-hosted`); delete `CI_RUNNER` and stop and ask.

### 5. The fork locks

```sh
V=$(gh api repos/$GH_REPO -q .visibility)
[ "$V" = private ] && gh api repos/$GH_REPO/actions/permissions/fork-pr-workflows-private-repos -q .run_workflows_from_fork_pull_requests
[ "$V" = public ] && gh api repos/$GH_REPO/actions/permissions/fork-pr-contributor-approval -q .approval_policy
grep -c "head.repo.full_name != github.repository" .github/workflows/tests.yml .github/workflows/compile-check.yml
gh api 'repos/nwnxee/unified/pulls?state=closed&per_page=50' -q '[.[] | select(.head.repo != null and .head.repo.full_name != "nwnxee/unified")][0] | {pull_request: .}' > /tmp/fork-event.json
scp /tmp/fork-event.json $DEPLOY_USER@$MACHINE: && ssh $DEPLOY_USER@$MACHINE 'sudo docker run --rm -v ~/fork-event.json:/tmp/e.json:ro -e GITHUB_EVENT_PATH=/tmp/e.json -e GITHUB_EVENT_NAME=pull_request -e GITHUB_REPOSITORY=nwnxee/unified --entrypoint /home/runner/hooks/job-started.sh nwn-runner:2.338.2; echo "exit $?"; rm ~/fork-event.json'
```

Success: `false` for a private repository, or `all_external_contributors` for a public one (anything else: stop
and ask, and change nothing); `tests.yml:3` and `compile-check.yml:1`; `refused: a pull request from ..., not from
nwnxee/unified itself ...` and `exit 1` (a real fork's pull request event from a public repository, given to the
hook).

### 6. The haks cache

Only when `NWSYNC_URL` is set in `tests.yml`.

```sh
ssh $DEPLOY_USER@$MACHINE 'ls /srv/nwn-runners/cache/nwsync; ls /srv/nwn-runners/cache/nwsync/*/hak | head -3'
gh run view $RUN -R $GH_REPO --log | grep -oE 'content [0-9a-f]{40}: (already on this machine|[0-9]+ files checked.*)' | sort | uniq -c
```

Success: one folder per version, named by 40 hex characters, with your haks in it; at most one `files checked` line
per version and lane, and `already on this machine` lines for the others.

### 7. Pictures

Only when a person has copied their own game to `GAME_DIR` (chapter 8, step 15) and named it in step 3.

```sh
ssh $DEPLOY_USER@$MACHINE "ls $GAME_DIR/data/nwn_base.key && sudo grep ^GAME_DIR /etc/nwn-runners/runners.conf"
cp "$GUIDE/templates/module/.github/workflows/previews.yml" .github/workflows/ && cp "$GUIDE/templates/module/tools/previews.sh" tools/ && git status -s
```

Success: the key file and `GAME_DIR=` that folder; two new files. **Ask first** before you commit them and open a
pull request; then, on the person's next pull request that changes an area:

```sh
PR=<that pull request's number>; gh api repos/$GH_REPO/issues/$PR/comments -q '.[] | select(.body | startswith("<!-- previews -->")) | .body' | head -6
```

Success: `### Pictures of the changed areas` and a table with a row per area and view. `could not draw` in a row:
read that run's log and report it.

### 8. Stills (by hand, only when a person asks)

Needs the CD key from a person (see Secrets) and chapter 8, step 16's packages on `MACHINE`.

```sh
ssh $DEPLOY_USER@$MACHINE 'test -s ~/.local/share/Neverwinter\ Nights/cdkey.ini && stat -c %a ~/.local/share/Neverwinter\ Nights/cdkey.ini'
ssh $DEPLOY_USER@$MACHINE "python3 ~/nwn-director/director.py film MODULE.mod --spot AREA@X,Y --stills 4 --character CHARACTER.bic --game $GAME_DIR --out ~/stills > ~/director.log 2>&1; echo exit \$?; tail -3 ~/director.log; ls ~/stills/*/"
```

Success: `600`; `exit 0` and four `.png` files and a `-sheet.png`. `CD Key is still in use`: the key is in a game
somewhere else; tell the person, and try again only after they say it's free.

## Verify

```sh
ssh $DEPLOY_USER@$MACHINE 'systemctl is-active nwn-runners; sudo runners.sh status | grep -c "online busy"'
gh api repos/$GH_REPO/actions/runners -q '[.runners[] | select(.status == "offline")] | length'
gh run list -R $GH_REPO -L 5 --json workflowName,conclusion -q '.[] | "\(.workflowName) \(.conclusion)"'
```

Success: `active`; `SLOTS`; `0` offline runners (a few for a minute after a restart is normal); the recent runs
green.

## Roll back

- **Back to GitHub's machines, at once:** `gh variable delete CI_RUNNER -R $GH_REPO`. Every later job runs there.
- **The runners:** `sudo systemctl disable --now nwn-runners` on `MACHINE` (it removes the containers and the
  runners' registrations), then `sudo rm -r /etc/nwn-runners /srv/nwn-runners` and `sudo docker volume prune -a`
  for the slots' images. A person deletes the token on GitHub.
- **The pictures:** delete `previews.yml`; the `previews` branch can be deleted by a person.

Nothing here touches the game host, the live game or its data.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- the token and the CD key: a person makes and places them; never read, print, copy or move them;
- step 4 (`CI_RUNNER`), and any pull request you would open;
- a `MACHINE` that runs a game server, or a request to put runners there;
- changing a repository's fork settings, or an organisation's runner group;
- copying the game anywhere: it is the person's own copy;
- running director stills while the person may be playing on that CD key.
