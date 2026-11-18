# Playbook 6. The module in git, checked and on the server (tier 1)

For an agent. The chapter for people is [`chapters/06-module.md`](../chapters/06-module.md). Follow the steps in
order. Do not go on from a step whose check fails.

`GUIDE` below is the root of this repository on the person's computer.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `GUIDE` | Where this repository is | none: a person gives it |
| `REPO_DIR` | The folder to create for the module's repository | `~/mymodule` |
| `MODULE_FILE` | The `.mod` to bring in. Leave empty to use the demo module from the server | empty |
| `MODULE_NAME` | The built module's name: letters, digits, underscores, at most 16 characters | `mymodule` |
| `SERVER` | The server's address or name | none: a person gives it |
| `DEPLOY_USER` | The account made in playbook 1 | `nwn` |
| `GH_REPO` | The GitHub repository to create, as `owner/name` | none: a person gives it |

Secrets: none pass through you. GitHub access is the person's own `gh` login, already set up. The workflow uses no
secrets.

## Preconditions

The tools are installed, the game is found, and playbooks 4 and 5 are done:

```sh
nasher --version | head -1; command -v nwn_script_comp >/dev/null && echo "compiler ok"; ls "$NWN_ROOT/data/nwn_base.key" >/dev/null && echo "game ok"; gh auth status >/dev/null 2>&1 && echo "gh ok"; ls -d "$REPO_DIR" 2>/dev/null | wc -l
ssh $DEPLOY_USER@$SERVER 'cd game && docker compose ps --format "{{.Service}} {{.Health}}"'
```

Success: `nasher 1.2.2`, `compiler ok`, `game ok`, `gh ok`, `0`, then `mariadb healthy` and `nwserver healthy`. If
a tool is missing, the chapter's steps 1 and 2 install it; a person sets `NWN_ROOT`. If `REPO_DIR` exists, stop and
ask.

## Steps

### 1. Start the repository from the template

```sh
cp -r "$GUIDE/templates/module" "$REPO_DIR" && cd "$REPO_DIR" && git init -q -b main && sed -i "s|^file = .*|file = \"$MODULE_NAME.mod\"|" nasher.cfg && ./tools/setup.sh | tail -1
```

Success: `abortOnCompileError = "true"`. Run every later command in `REPO_DIR`.

### 2. Bring the module in

With a module from the person:

```sh
nasher unpack --file "$MODULE_FILE" --yes | tail -1
```

Or, when `MODULE_FILE` is empty, the demo module from the server:

```sh
ssh $DEPLOY_USER@$SERVER 'docker cp game-nwserver-1:/nwn/data/data/mod/DockerDemo.mod /tmp/DockerDemo.mod' && scp $DEPLOY_USER@$SERVER:/tmp/DockerDemo.mod . && nasher unpack --file DockerDemo.mod --yes | tail -1
```

Success: a line starting `Converting`, and `find src -type f | wc -l` prints more than `0` (14 for the demo
module).

### 3. Fetch the NWNX script files the module's scripts include

For the demo module, add the example script and the one file it includes:

```sh
mkdir -p src/nss && cp example/mod_load.nss src/nss/ && sed -i 's/"value": "x2_mod_def_load"/"value": "mod_load"/' src/ifo/module.ifo.json
```

For any module, list the NWNX files its scripts include and fetch each from the server's own NWNX version:

```sh
REV=$(ssh $DEPLOY_USER@$SERVER "docker inspect game-nwserver-1 -f '{{index .Config.Labels \"org.opencontainers.image.revision\"}}'")
grep -rhoE '#include +"nwnx_[a-z_]+"' src/nss | grep -oE 'nwnx_[a-z_]+' | sort -u
curl -fsSL -o src/nss/nwnx_sql.nss https://raw.githubusercontent.com/nwnxee/unified/$REV/Plugins/SQL/NWScript/nwnx_sql.nss
```

Success for the demo module: the list is `nwnx_sql`, and `src/nss/nwnx_sql.nss` exists. For a person's own module
the files are usually there already; fetch only the missing ones, and stop and ask if a file is not at that
address (each plugin's file is in its own folder under `Plugins/`).

### 4. Build and check

```sh
nasher pack --yes | tail -1; python3 tools/check_compiled.py $MODULE_NAME.mod src
```

Success: `Success: packed $MODULE_NAME.mod`, then `... every script with an entry point is compiled`.

### 5. Prove the check can fail

```sh
printf 'void main()\n{\n    ThisFunctionDoesNotExist();\n}\n' > src/nss/zz_broken.nss; nasher pack --yes >/dev/null 2>&1; echo "exit $?"; rm src/nss/zz_broken.nss
```

Success: `exit 1`. If it prints `exit 0`, step 1's setup did not take: stop and ask.

### 6. Commit

```sh
git add -A && git commit -q -m "The module as text" && git status -s | wc -l && git ls-files | grep -c '\.mod$'
```

Success: `0` and `0`. Nothing is left over, and no `.mod` is in git.

### 7. Create the GitHub repository and push

**Ask first.** Tell the person the repository's name and that it will be private, and wait for a yes.

```sh
gh repo create $GH_REPO --private --source . --push
```

Success: the last line says the branch `main` tracks `origin/main`.

### 8. Watch the first check

```sh
sleep 10; RUN=$(gh run list -R $GH_REPO -L 1 --json databaseId -q '.[0].databaseId'); gh run watch $RUN -R $GH_REPO --exit-status >/dev/null; echo "exit $?"
```

Success: `exit 0`. It took 34 seconds on the test. On a failure, read `gh run view $RUN -R $GH_REPO --log-failed`
and stop and ask.

### 9. Put the checked module on the server

**Ask first if players may be on the server.** This restarts the game.

```sh
rm -rf /tmp/module-artifact && gh run download $RUN -R $GH_REPO -n module -D /tmp/module-artifact && scp /tmp/module-artifact/$MODULE_NAME.mod $DEPLOY_USER@$SERVER:
ssh $DEPLOY_USER@$SERVER "sudo cp ~/$MODULE_NAME.mod ~/game/home/modules/ && cd game && sed -i 's|^NWN_MODULE=.*|NWN_MODULE=$MODULE_NAME|' .env && docker compose up -d && for i in \$(seq 60); do s=\$(docker inspect -f '{{.State.Health.Status}}' game-nwserver-1); [ \"\$s\" = healthy ] && break; sleep 2; done; echo \$s"
```

Success: the last line is `healthy`.

## Verify

```sh
"$GUIDE/templates/game/nwn-status.py" $SERVER
```

Success: `... is up: module $MODULE_NAME, ...`.

For the demo module, the example script's row:

```sh
ssh $DEPLOY_USER@$SERVER 'cd game && docker compose exec -T mariadb sh -c "mariadb -u\"\$MARIADB_USER\" -p\"\$MARIADB_PASSWORD\" \"\$MARIADB_DATABASE\" -N -e \"SELECT COUNT(*) FROM server_starts\""'
```

Success: `1` or more.

```sh
gh run list -R $GH_REPO -L 1 --json conclusion -q '.[0].conclusion'
```

Success: `success`.

## Roll back

- **The server:** set `NWN_MODULE` back to the earlier name in `~/game/.env` and run `docker compose up -d`. The
  earlier module's file is still in `home/modules` (the demo module is inside the image and is always there).
- **The repository:** nothing on the person's computer or server depends on it yet. A person deletes a GitHub
  repository; you do not.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- creating a GitHub repository, or making one public;
- pushing straight to `main` after the first push. From then on: a branch and a pull request, every time;
- step 9 on a server that may have players on it;
- merging a pull request whose check is not green;
- a script the compiler skips (it is missing from the built module but has no error);
- anything that would put a built `.mod` or a secret into git.
