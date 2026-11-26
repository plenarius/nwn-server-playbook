# Playbook 4, tier 3. Your own NWNX image

For an agent. The chapter for people is [`chapters/04-game-server.md`](../chapters/04-game-server.md), section
"Tier 3". Follow the steps in order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer, except where a step says `cd`.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `GAME` | The game host's public address | none: a person gives it |
| `DEPLOY_USER` | The deploy user on the game host | `nwn` |
| `NWNX_REPO` | The person's copy of NWNX on GitHub, as `owner/name` | none: a person gives it |
| `PLUGIN` | The plugin's name, as in `Plugins/<PLUGIN>` | `Hello` |
| `WORK` | An empty folder for the clone | `$(mktemp -d)` |

Secrets: none pass through you. The workflow uses GitHub's own short-lived token. If the package is private, a
person logs the game host in to GHCR with a token that has only `read:packages` (chapter, step 27); never ask for
that token and never read `~/.docker/config.json`.

## Before you start: what a person does

1. Creates `NWNX_REPO` on GitHub: a fork of `nwnxee/unified` (public), or an empty private repository.
2. Decides whether the package will be public. A private one needs step 27 of the chapter on the game host.
3. Says yes to a restart of the game (step 5 restarts it).

## Preconditions

```sh
gh repo view $NWNX_REPO --json visibility,defaultBranchRef -q '.visibility + " " + (.defaultBranchRef.name // "empty")'
ssh $DEPLOY_USER@$GAME 'cd game && grep ^NWNX_IMAGE= .env && docker compose ps --format "{{.Service}} {{.Health}}" | grep nwserver'
```

Success: the repository's visibility and `master` (or `empty`); the game's current image line, which you write down
for Roll back; `nwserver healthy`.

## Steps

### 1. The source, with the plugin and the workflow

```sh
PB=$(pwd); cd $WORK && git clone -q https://github.com/nwnxee/unified.git && cd unified
git remote add mine git@github.com:$NWNX_REPO.git
git rm -q .github/workflows/*.yml && mkdir -p .github/workflows
cp -r $PB/templates/nwnx/Plugins/Hello Plugins/
cp $PB/templates/nwnx/image.yml .github/workflows/image.yml
cp $PB/templates/nwnx/image.Dockerfile image.Dockerfile
git add -A && git commit -q -m "Our own image workflow and our plugin" && git log --oneline -1
```

`$PB` is this repository; steps 2 to 5 run from the clone, Verify and Roll back from `$PB` again. For a plugin
other than `Hello`, the person's plugin folder goes into `Plugins/` instead. If `NWNX_REPO` is a fork that already has commits of its own, stop and ask: merge, don't replace.

Success: one line with the new commit.

### 2. Push, and the first build

```sh
git push -q mine master
for i in $(seq 60); do
  RUN=$(gh run list -R $NWNX_REPO --commit $(git rev-parse HEAD) --limit 1 --json databaseId -q '.[0].databaseId'); [ -n "$RUN" ] && break
  [ $i -gt 6 ] && gh workflow run image.yml -R $NWNX_REPO --ref master 2>/dev/null && sleep 20 && RUN=$(gh run list -R $NWNX_REPO --limit 1 --json databaseId -q '.[0].databaseId') && break
  sleep 20
done; echo "run ${RUN:-none}"
gh run watch $RUN -R $NWNX_REPO --exit-status > /dev/null && echo green
TAG=$(git rev-parse --short=7 HEAD); echo $TAG
```

A new repository can take several minutes to notice its workflow; the loop waits up to 20 minutes for a run and
starts one by hand after two. The first build takes about 11 minutes; run the watch in the background if your shell has a time limit.

Success: `run` and a number, `green`, then the commit tag. `run none` means GitHub never saw the workflow: stop and
ask. A red `image` job whose log says `is already in the registry` means this
commit was built before: stop and ask.

### 3. The game host can pull it

```sh
ssh $DEPLOY_USER@$GAME "docker pull -q ghcr.io/${NWNX_REPO,,}:$TAG > /dev/null && docker image inspect ghcr.io/${NWNX_REPO,,}:$TAG -f '{{index .Config.Labels \"org.opencontainers.image.revision\"}}' | cut -c1-7"
```

Success: the same seven characters as `$TAG`. `denied` or `unauthorized` means the package is private and the host
isn't logged in: a person does the chapter's step 27, then run this again.

### 4. The plugin's script file on the server

```sh
scp Plugins/$PLUGIN/NWScript/*.nss $DEPLOY_USER@$GAME:
ssh $DEPLOY_USER@$GAME 'cd game && sudo mkdir -p home/development && sudo cp ~/nwnx_*.nss home/development/ && rm ~/nwnx_*.nss && sudo ls home/development | grep nwnx_'
```

Success: the plugin's `nwnx_*.nss` file name.

### 5. The game on the commit tag, with the plugin on

**Ask first.** This restarts the game: players are disconnected for about ten seconds.

```sh
P=$(echo $PLUGIN | tr a-z A-Z); IMG=ghcr.io/${NWNX_REPO,,}:$TAG
ssh $DEPLOY_USER@$GAME "docker image inspect $IMG > /dev/null && cd game && sed -i 's|^NWNX_IMAGE=.*|NWNX_IMAGE=$IMG|' .env && (grep -q '^NWNX_${P}_SKIP=' .env || echo 'NWNX_${P}_SKIP=n' >> .env) && docker compose up -d 2>&1 | tail -1"
ssh $DEPLOY_USER@$GAME 'for i in $(seq 60); do s=$(docker inspect -f "{{.State.Health.Status}}" game-nwserver-1); [ "$s" = healthy ] && break; sleep 3; done; echo "$s $(docker inspect -f "{{.Config.Image}}" game-nwserver-1)"'
```

The settings file is changed only once the image is on the host (step 3), so a failed pull can't leave the game
pointing at an image it doesn't have.

On a game run by Coolify (tier 2), change `NWNX_IMAGE` and add the switch in the service's settings instead, then
**Restart** it, and use its container's name in Verify.

Success: `healthy` and the image `$IMG`. Any other image means the game didn't move: stop and ask.

## Verify

```sh
cd $PB
scp templates/nwnx/console.py $DEPLOY_USER@$GAME:
ssh $DEPLOY_USER@$GAME "docker inspect -f '{{.Config.Image}}' game-nwserver-1; docker logs game-nwserver-1 2>&1 | grep -c 'Loaded plugin.*NWNX_$PLUGIN.so'"
ssh $DEPLOY_USER@$GAME 'timeout 20 python3 console.py game-nwserver-1 "evalx WriteTimestampedLogEntry(NWNX_Hello_Greet(\"Tester\"));" | grep "(Server)"; rm console.py'
templates/game/nwn-status.py $GAME
```

Success: the image by its commit tag; a count of at least `1`; `Hello, Tester, from your own NWNX plugin` (for
another plugin, ask the person for a call that shows it working); the game answering from outside.

## Roll back

Put back the image line written down in Preconditions:

```sh
ssh $DEPLOY_USER@$GAME "cd game && sed -i 's|^NWNX_IMAGE=.*|NWNX_IMAGE=PREVIOUS_IMAGE|' .env && docker compose up -d 2>&1 | tail -1"
```

The plugin switch may stay: a missing plugin is skipped with a warning. Ask before this restart, as in step 5. The
commit tags in the registry stay; never delete package versions, they're the only history of builds.

## Stop and ask

- Before every restart of the game (step 5, Roll back).
- When the workflow refuses a tag (`is already in the registry`), or a build fails to compile.
- When the game host can't pull: a person logs it in or makes the package public.
- Before changing the package's visibility, deleting a package version, or changing `BASE_IMAGE`.
- Before merging upstream into a copy that has commits of its own.
