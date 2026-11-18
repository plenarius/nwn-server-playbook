# Chapter 6. Your module in git

**Status:** tier 1 is written and tested. Tier 2 (a test server that runs your scripts, staged releases) and tier 3
(choosing which tests to run, test lanes) are not written yet.

## What you learn

How to keep your module as text files in a git repository, build the `.mod` from them with a tool called nasher,
have every change checked automatically, and put the result on your server.

When you're done, you'll have:

- your module as a folder of text files, where every change is a line you can read, review and undo;
- one command that builds the `.mod` from those files;
- a check, running on every pull request, that fails when a script doesn't compile;
- your module running on the server from chapter 4, with a script in it writing to the database from chapter 5.

If you've only ever worked in the toolset and saved a `.mod`, this chapter is the biggest change of habit in tier
1. It's also the one I'd least like to be without. A `.mod` is one opaque file. Text in git is history, review and
a way back, for you and for everyone who builds with you.

**Time:** about half an hour the first time. The automatic check itself took 31 to 35 seconds on GitHub's machines
during the test.

## What Layonara does

- **Text, not a `.mod`.** Our module is 14,829 text files in git. Nobody commits a `.mod`; it is built from the
  files whenever one is needed.
- **nasher builds it.** nasher turns the text files back into the game's formats, compiles every script and packs
  the module.
- **Every pull request is checked** before anyone merges it, in four to five minutes: script style, 17 checks of
  the content itself, a full compile, and a check that the compiled scripts are really there.
- **Versions are pinned.** The check names the exact versions of nasher and of the compiler it uses, so a build
  today and a build next month mean the same thing.
- **A small target for quick starts.** Beside the full module we can build a nine-area one that starts in seconds.
  That is tier 2.

## The human playbook

Each step carries a label: GENERIC (the same for any server), ADAPT (works once you change the things it names) or
LAYONARA-ONLY (something we do that you probably shouldn't copy).

The files for this chapter are in [`templates/module`](../templates/module): the start of a repository for your
module. The steps below use the small demo module from chapter 4 as the example, so that you can follow along even
before you have a module of your own. Where your own module goes instead, the step says so.

The commands are for Linux. nasher and the compiler also come for macOS and Windows, from the same download pages.

### 1. GENERIC. Install the two tools

You need **nasher** and the **neverwinter.nim** tools, which include the script compiler. Both are single files you
download; nothing gets installed system-wide.

```sh
mkdir -p ~/nwn-tools && cd ~/nwn-tools
curl -fsSL -o nasher.tar.gz https://github.com/squattingmonk/nasher/releases/download/1.2.2/nasher_linux.tar.gz
curl -fsSL -o neverwinter.zip https://github.com/niv/neverwinter.nim/releases/download/2.3.2/neverwinter-x86_64-linux-gnu.zip
tar xzf nasher.tar.gz nasher && unzip -oq neverwinter.zip
export PATH=~/nwn-tools:$PATH
nasher --version
```

You should see `nasher 1.2.2`. Add the `export PATH` line to your shell's startup file so the tools are there next
time.

### 2. ADAPT. Tell the tools where the game is

Change: the path to your game.

The compiler needs the game's own scripts, so it needs to know where your copy of the game is. Point `NWN_ROOT` at
the folder that has a `data` folder with `nwn_base.key` in it. For a Steam install on Linux that is:

```sh
export NWN_ROOT="$HOME/.local/share/Steam/steamapps/common/Neverwinter Nights"
ls "$NWN_ROOT/data/nwn_base.key"
```

If the `ls` prints the file's name, you're set. This line belongs in your shell's startup file too.

### 3. GENERIC. Start your repository from the template

From this repository:

```sh
cp -r templates/module ~/mymodule
cd ~/mymodule
git init -b main
./tools/setup.sh
```

The last command changes one nasher setting for this folder: stop when a script fails to compile. Step 6 shows why
that matters.

Have a look at `nasher.cfg`. It's short. The line `file = "mymodule.mod"` is the name of the module that gets
built, and the name your server will load. Change it to your module's name whenever you like, and keep it to
letters, digits and underscores.

### 4. ADAPT. Bring a module in

Change: which module.

**If you have a module of your own,** this one command turns it into text:

```sh
nasher unpack --file /path/to/YourModule.mod --yes
```

**To follow along with the demo module,** fetch it from your server first:

```sh
ssh nwn@SERVER 'docker cp game-nwserver-1:/nwn/data/data/mod/DockerDemo.mod /tmp/DockerDemo.mod'
scp nwn@SERVER:/tmp/DockerDemo.mod .
nasher unpack --file DockerDemo.mod --yes
```

Either way, look in `src/` afterwards. There is a folder for each kind of thing: `are` and `git` for areas, `ifo`
for the module's own settings, `nss` for scripts if the module has any, and so on. Each file is plain text. Open
`src/ifo/module.ifo.json` and you can read your module's settings line by line. This is what git will track from
now on.

### 5. GENERIC. Add a script, and build

The demo module has no scripts of its own, so here is a small one to work with. It runs once when the module loads
and writes a row to the database from chapter 5:

```sh
mkdir -p src/nss
cp example/mod_load.nss src/nss/
```

It uses the SQL plugin, so it needs that plugin's script file beside it. This is the rule from chapter 4 in
practice: a script that includes `nwnx_sql` needs `nwnx_sql.nss` in the module and `NWNX_SQL_SKIP=n` on the server.
Fetch the file for the exact NWNX version your server runs. This asks the server which version that is:

```sh
REV=$(ssh nwn@SERVER "docker inspect game-nwserver-1 -f '{{index .Config.Labels \"org.opencontainers.image.revision\"}}'")
curl -fsSL -o src/nss/nwnx_sql.nss https://raw.githubusercontent.com/nwnxee/unified/$REV/Plugins/SQL/NWScript/nwnx_sql.nss
```

Now tell the module to run the script when it loads. Open `src/ifo/module.ifo.json` in a text editor, find
`"Mod_OnModLoad"`, and change its value from `x2_mod_def_load` to `mod_load`. (The example script still runs the
game's own load script first, so nothing is lost.) With your own module you'd normally set this in the toolset; I
want you to see that it is only a line of text.

Build it:

```sh
nasher pack --yes
python3 tools/check_compiled.py mymodule.mod src
```

You should see `Success: packed mymodule.mod`, and then `mymodule.mod: every script with an entry point is compiled
(1 checked)`.

### 6. GENERIC. Break a script on purpose

Before you trust a check, watch it fail. Make a script that can't compile:

```sh
printf 'void main()\n{\n    ThisFunctionDoesNotExist();\n}\n' > src/nss/broken.nss
nasher pack --yes; echo "exit status $?"
```

nasher prints the compile error, refuses to pack, and the exit status is `1`. That refusal comes from the setting
in step 3. Without it, nasher prints the same error and then builds a module anyway, without the broken script, and
reports success. I tried both. A module that is quietly missing a script is a nasty thing to find out from a
player.

`tools/check_compiled.py` is the second pair of eyes. It doesn't ask the build how it went. It opens the finished
`.mod` and checks that every script that should be compiled is in there. On a module built the careless way, it
said:

```
mymodule.mod has no compiled script for 1 of 2 scripts:
  broken.nss
```

Take the broken script out again:

```sh
rm src/nss/broken.nss
```

### 7. GENERIC. Commit

```sh
git add -A
git commit -m "My module as text"
```

`git status` before the commit is worth a look. The built `.mod` and nasher's working folder aren't in the list,
because `.gitignore` keeps them out. Only the text goes into git.

### 8. ADAPT. Put it on GitHub and let it check itself

Change: the repository's name, and whether it is private.

Create an empty repository on GitHub, private if you like, and push to it. With GitHub's command-line tool that is
one line:

```sh
gh repo create mymodule --private --source . --push
```

The template came with a workflow, `.github/workflows/compile-check.yml`. From now on GitHub builds your module on
its own machines on every pull request and every change to `main`, with the same two commands you ran in step 5. It
needs no secrets, and it never touches your server. Look under the repository's Actions tab: the first run has
already started.

To see it earn its keep, make a branch, add the broken script from step 6, push it and open a pull request. The
check turns red, and its log shows the same compile error you saw at home. Remove the script and push again, and it
turns green.

Two details in the workflow file are worth knowing:

- **It names its versions:** nasher, the compiler, and the NWNX image whose game data it compiles against. When you
  change the image tag on your server (chapter 4, step 11), change it here too.
- **It keeps the module it built** for 14 days. On the run's page, under Artifacts, you can download exactly the
  `.mod` that was checked.

### 9. GENERIC. Put the module on your server

Copy the `.mod` to the server, either the one you built or the one downloaded from the check:

```sh
scp mymodule.mod nwn@SERVER:
ssh nwn@SERVER
sudo cp ~/mymodule.mod ~/game/home/modules/
cd game
nano .env        # change NWN_MODULE=DockerDemo to NWN_MODULE=mymodule
docker compose up -d
```

The name in `.env` is the file's name without `.mod`. If you fetched `nwnx_sql.nss` into `home/development` in
chapter 5, you can delete it now (`sudo rm home/development/nwnx_sql.nss`). The module carries its own copy.

Check it. From your own computer:

```sh
templates/game/nwn-status.py SERVER
```

should now say `module mymodule`. And on the server, the script's own evidence:

```sh
docker compose exec mariadb sh -c 'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" -e "SELECT * FROM server_starts"'
```

One row, with the time your module loaded. Restart the game with `docker compose restart nwserver` and there are
two. A script that you keep in git, built by a tool, checked by a machine, is running on your server and
remembering things. That's the whole loop.

### 10. GENERIC. The everyday loop from here

1. Make a branch.
2. Change the module. Edit scripts in any editor. For areas and everything else, build the `.mod`, open it in the
   toolset, save, and run `nasher unpack --file mymodule.mod` to bring your changes back into the text files.
3. Commit, push, open a pull request.
4. When the check is green, merge.
5. Put the new `.mod` on the server as in step 9, at a quiet time. Your players are disconnected when the game
   restarts.

Tier 2 automates steps 4 and 5 and adds a test server that runs your scripts for real.

### 11. LAYONARA-ONLY. Our seventeen content checks

Our check also runs 17 small programs that know our world's rules: that every teleporter leads somewhere, that
every quest conversation names a quest that exists, and so on. Each one was written after something broke. Yours
will be different, and you don't need any on day one. When something breaks twice, that's the moment to write the
check for it.

## The agent playbook

If you work with an AI agent, [`playbooks/06-module.md`](../playbooks/06-module.md) has these same steps in a fixed
shape it can follow. It stops and asks you before it creates a repository, before it pushes, and before it touches
a server that players might be on.

## Lessons

These are the things that went wrong for us, written down so they don't have to go wrong for you.

- **A build can succeed without one of your scripts.** This is step 6, and it is the reason our own check opens the
  built module and counts. The older nasher we pin leaves a failed script out and still reports success. The newest
  one is much better at saying so, but only refuses to build when you ask it to, as `tools/setup.sh` does.
- **A script that borrows its `main` from an include compiles to nothing, without an error.** If a script's only
  content is an include that happens to hold the `main` function, the compiler skips it and says nothing is wrong.
  Put the line `void main();` above the include, and it compiles. I tested both on the day of writing: skipped
  without, compiled with. Neither nasher nor the check in this chapter can warn you about this one, so it is worth
  remembering.
- **Script names stop at 16 characters.** It's an old limit of the game's file format, and it applies to every
  script, area and item name. A script called `a_name_17_chars_x` failed to compile with "is not a valid resref".
  Count before you name things.
- **Pin your tools.** Our check names exact versions for a reason: a new compiler version once changed which
  scripts compile (the lesson above), and we'd rather meet that on a day we chose.
- **Keep the script files and the server image in step.** The NWNX script files in your module must come from the
  same NWNX version as the image on your server. Step 5 fetches them by the server's own version for that reason.

## Tested

On 2026-11-18, with nasher 1.2.2, neverwinter.nim 2.3.2 and the demo module from `nwnxee/unified:ed79330`:

- installing the tools from the download links, and building with a Steam copy of the game as `NWN_ROOT`;
- a new repository from the template, unpacking the demo module, adding the example script, building, checking;
- a broken script with the setting from `tools/setup.sh` (nasher refuses, exit status 1) and without it (nasher
  builds a module without the script and reports success), and the check catching the second case;
- the two lessons about `void main();` and 16-character names;
- the workflow on GitHub's own machines, in a private repository: a passing run on `main` (34 seconds), a pull
  request with a broken script (failed, with the compile error in its log), and the same pull request fixed
  (passed);
- downloading the module that the passing run built, and putting that file on a fresh test server that had been
  through chapters 1, 4 and 5: the server loaded it, the status tool reported `module mymodule`, and the example
  script wrote one row at the first start and a second at the next.

Not tested: the tools on macOS and Windows, a large module of your own (ours takes four to five minutes to check,
the demo takes seconds), and the round trip through the toolset in step 10.
