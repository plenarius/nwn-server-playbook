# Playbook 7, tier 3. Compiled models, and NWSync builders can read

For an agent. The chapter for people is [`chapters/07-haks-nwsync.md`](../chapters/07-haks-nwsync.md), section
"Tier 3". Follow the steps in order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer, unless it says otherwise.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `CONTROL` | The control host's public address | none: a person gives it |
| `DEPLOY_USER` | The deploy user there | `nwn` |
| `NWSYNC_HOST` | The name players download from, served from the control host (tier 2) | none: a person gives it |
| `CONTENT_DIR` | The person's own checkout of the content repository | `~/myhaks` |
| `MODULE` | The module file on the control host that `publish.sh` is given | none: a person gives it |
| `GAME_INSTALL` | The person's game install, the folder holding `data/nwn_base.key` | none: a person gives it |
| `IMAGE` | The new builder image's name | `nwsync-builder:2.3.2-cm4.18.3` |
| `BUILDERS` | Whether to write the builders' version | `no`: only a person sets `yes` |

Secrets: none. The control host's key and the content repository's deploy key are tier 2's.

## Preconditions

Playbook 7, tier 2 is done: the control host stages, and the address serves.

```sh
ssh $DEPLOY_USER@$CONTROL 'ls ~/content/publish.sh ~/content/content.env ~/myhaks/.git > /dev/null && echo ok'
curl -s -m 10 https://$NWSYNC_HOST/latest; echo
ls "$GAME_INSTALL/data/nwn_base.key"; git -C $CONTENT_DIR status -s | wc -l
```

Success: `ok`, a 40-character version, the key file's path, and `0` (a clean checkout). Anything else: stop and
ask.

## Steps

### 1. The game's data on the control host

**Ask first**: it copies about 4.5 GB to the control host. After the person's yes:

```sh
ssh $DEPLOY_USER@$CONTROL 'df -h --output=avail ~ | tail -1'
rsync -a "$GAME_INSTALL/data/" $DEPLOY_USER@$CONTROL:nwn-data/data/
ssh $DEPLOY_USER@$CONTROL 'ls ~/nwn-data/data/nwn_base.key && du -sh ~/nwn-data'
```

Success: at least 10G free before the copy, then the key's path and a size of about `4.5G`. Never put this folder
under `~/nwsync`.

### 2. The scripts and the new image

```sh
scp -q -r templates/content/* $DEPLOY_USER@$CONTROL:content/
ssh $DEPLOY_USER@$CONTROL "docker build -q -t $IMAGE ~/content/builder > /dev/null && docker run --rm $IMAGE cleanmodels --version"
ssh $DEPLOY_USER@$CONTROL "grep -q '^IMAGE=' ~/content/content.env || printf 'IMAGE=%s\nMODELS=compile\n' $IMAGE >> ~/content/content.env; grep -E '^(IMAGE|MODELS)=' ~/content/content.env"
```

Success: `cleanmodels v4.18.3 ...`, then `IMAGE=` the new image and `MODELS=compile`. If `IMAGE=` was already set
to another image, stop and ask: don't change it.

### 3. The new build.sh in the content repository

```sh
cd $CONTENT_DIR && git checkout -q -b compiled-models
/bin/cp "$OLDPWD/templates/haks/build.sh" build.sh && git add build.sh && git commit -qm "Compile models in the build" && git log -1 --format=%s
```

Success: `Compile models in the build`. Push the branch and open a pull request with the person's `gh` login. The
person merges it; wait for their word.

### 4. Stage with compiled models

Nothing reaches players: `latest` is not touched.

```sh
ssh $DEPLOY_USER@$CONTROL "~/content/publish.sh $MODULE < /dev/null" | grep -v '^packed'
```

Success: `N ASCII models`, `checked ...`, `compiled N models, M of them from the cache`, then tier 2's lines ending
in `staged` and `players still get`. Run it a second time: `checked N unchanged models by their checksum, 0 with
cleanmodels` and `M` equal to the number of models compiled.

Failures:

- `the game's data is not in reach`: step 1 is missing or isn't a game install. Stop and ask.
- `these models fail their check; nothing was packed:` or `a model in ... did not compile`: report the lines as
  they are and stop. Fixing a model is the modeller's job, not yours. Nothing is staged now, which is safe.

### 5. The origins files

```sh
ssh $DEPLOY_USER@$CONTROL "docker run --rm $IMAGE nwsync-origins https://$NWSYNC_HOST"
```

Success: `version <latest>: N files from H haks and talk tables`, then one line per hak and talk table the
module lists. `has no origins file` or `does not match its manifest`: stop and ask.

### 6. The builders' version (only if the person set `BUILDERS=yes`)

**Ask first**, and only on the person's word: it adds a second address builders read. After their yes:

```sh
ssh $DEPLOY_USER@$CONTROL 'grep -q "^BUILDERS=" ~/content/content.env || echo BUILDERS=yes >> ~/content/content.env; grep "^BUILDERS=" ~/content/content.env'
```

Success: `BUILDERS=yes`. The person restarts the downloads service once in Coolify (it reads the `Caddyfile` from
step 2 only when it starts); wait for their word, then:

```sh
ssh $DEPLOY_USER@$CONTROL "~/content/publish.sh $MODULE < /dev/null" | grep '^builders get'
curl -sI https://$NWSYNC_HOST/builders/latest | grep -i '^cache-control'
ssh $DEPLOY_USER@$CONTROL "docker run --rm $IMAGE nwsync-origins https://$NWSYNC_HOST/builders"
```

Success: `builders get <version> (N files) at https://NWSYNC_HOST/builders`, `cache-control: no-store`, and every
hak the build made in the list, the ones the module doesn't list too.

## Verify

```sh
ssh $DEPLOY_USER@$CONTROL 'cd ~/myhaks && git status -s | wc -l && du -sh ~/model-cache'
ssh $DEPLOY_USER@$CONTROL "docker run --rm $IMAGE nwsync-origins https://$NWSYNC_HOST latest \$(docker run --rm -v ~/myhaks:/src $IMAGE sh -c 'ls /src/haks/*/*.mdl | head -1 | xargs basename')"
```

Success: `0` (the build never writes to the checkout), a cache size above zero, and a model's name with the hak
it comes from, or `(not in ...)` if its hak isn't in what players get: not promoted yet, or not in the module at all.

## Roll back

Nothing in this playbook reaches players until the person promotes (tier 2's step 9).

- Compiling: set `MODELS=ascii` in `~/content/content.env` (or remove the line) and stage again. The old
  `build.sh` packs models as they are; revert step 3's commit to go back to it entirely.
- The image: set `IMAGE=` back to the old image in `content.env`. Never remove a builder image yourself.
- The builders' version: set `BUILDERS=no`. Its `latest` stays until the person removes `~/nwsync/builders`.
- The model cache can be deleted at any time (`rm -rf ~/model-cache`); the next build compiles everything again.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- step 1 (the copy) and step 6 (the builders' version), always;
- any model refused or failing to compile: report it, never edit, remove or skip a model to make the build pass;
- changing cleanmodels' or the tools' version or checksum in the `Dockerfile`, or removing a builder image;
- promoting (tier 2's step 9), deleting anything under `~/nwsync`, or `~/nwn-data`.
