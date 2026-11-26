# Chapter 6. Your module in git

**Status:** tiers 1 and 2 are written and tested. Tier 3 (choosing which tests to run, test lanes) is not written
yet.

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

## Tier 2. Tests on a real server, a staging copy, and releases by tag

### What you learn

How to have your scripts run for real, on the same NWNX server your players use, every time someone opens a pull
request. And how to turn a release into one command: you push a tag, and a few minutes later the exact module
that passed its tests is waiting on a staging copy of your game, with yesterday's world in it, for you to try
before anyone else does.

When you're done, you'll have:

- a folder of small test scripts, and one command that runs them all on a headless NWNX server with a database of
  its own, then says plainly what passed and what didn't;
- the same tests on GitHub's machines on every pull request, with the logs kept for each run;
- a second, private copy of your game on the game host, the **staging** copy, on its own port and with its own
  database;
- a release workflow: push a tag such as `v1.4.0`, and it tests, builds, makes a GitHub release with the module
  attached, and puts that file on staging;
- going live as one short, unhurried step that stays yours.

The headless server ("headless" means nobody logs in: no game client, no screen) is what makes this possible.
Your test scripts run inside the real game, with the real NWNX plugins and a real MariaDB, so a test that passes
here means the script really works on that server.

**Time:** about an hour the first time, most of it the staging copy. On the test, a run of the example tests took
17 to 20 seconds at home and under a minute on GitHub, and a release from `git push` of the tag to a healthy
staging game took under two minutes.

You need chapter 6's tier 1 done (your module in git, with the compile check), chapter 12's nightly backup, and
chapter 4's tier 2 (Coolify managing the game host). Chapter 8 explains the GitHub side of all this in more depth:
what the machines are, what is cached and how the staging secret is kept.

### What Layonara does

- **About five hundred tests.** Each is a small script named after the system it tests and the case, such as a
  bank's deposit or a door's lock. The runner runs them one at a time inside a headless server and turns the
  server's log into a report.
- **A fresh world for every run.** The test server gets a new MariaDB that lives in memory and starts from a small
  seed with no player data in it, and it sits on a network with no route out, so a test can never post to our
  Discord or reach the live game.
- **Strict about what counts as a pass.** A test fails for a failed assert, for running too long, for a script
  error, or for leaving things behind in the world (a creature it made, an item it dropped).
- **What runs when.** Pull requests run the tests their change can reach; every night runs all of them. Those are
  tier 3 ideas, and so are the parallel test lanes that run them; this tier runs everything, every time, which is
  right while your suite is small.
- **Every release is staged before it is live.** A merge builds the module and stages it beside the live one on the
  game host; a tag such as `v8.4` rebuilds it with that version written into it and stages it again. Nothing is
  live until one of us presses the button that swaps it in and restarts the game. Six releases in ten days, at the
  time of writing.
- **A separate server for trying things.** We try releases on a dev server of their own, which is tier 3. Here I
  suggest something smaller that does both jobs: one staging copy on the game host, which holds the next release
  and can be played.

### The human playbook

The files are in [`templates/module`](../templates/module): `tests/` (the runner, the example tests, the test
server's Compose file and `run.sh`), `.github/workflows/tests.yml` and `release.yml`, and
`.github/actions/nwn-tools` (the tool install the two workflows share). For staging, on the game host:
[`templates/game/staging.yaml`](../templates/game/staging.yaml) and
[`templates/game/stage.sh`](../templates/game/stage.sh).

#### 12. GENERIC. Bring the tests into your repository

If you started your module from the template after this section existed, you already have everything. Otherwise,
from this repository:

```sh
cp -r templates/module/tests ~/mymodule/
mkdir -p ~/mymodule/.github/actions
cp -r templates/module/.github/actions/nwn-tools ~/mymodule/.github/actions/
cp templates/module/.github/workflows/tests.yml templates/module/.github/workflows/release.yml ~/mymodule/.github/workflows/
echo 'tests/.run/' >> ~/mymodule/.gitignore
```

and add a second build target to the end of `~/mymodule/nasher.cfg`, as in the template's:

```
[target]
name = "test"
description = "The module plus the tests in tests/nss, for tests/run.sh. Never put this one on a server."
file = "test.mod"

  [target.sources]
  include = "src/**/*.{nss,json}"
  include = "tests/nss/*.nss"
```

It is your module plus the scripts in `tests/nss`, built as `test.mod`. Your real module never contains the tests.
The two `include` lines are on purpose: nasher reads a repeated key as a list, and refuses the `["a", "b"]` form
that most TOML files would use. I found that out the slow way.

#### 13. GENERIC. Run them at home

You need Docker, the tools from step 1, and `NWN_ROOT` from step 2. Two of the example tests include `nwnx_sql`,
whose script file step 5 put in `src/nss`; if your module doesn't use the database, delete those two.

```sh
cd ~/mymodule
tests/run.sh
```

The first time, Docker downloads the NWNX image and MariaDB, which takes a minute or two. After that it is about
20 seconds, and the end of what it prints looks like this:

```
server ran for 17 s
PASS  t_db_roundtrip
PASS  t_delay_async
PASS  t_load_recorded
PASS  t_module_start
4 passed, 0 failed, 0 skipped
```

What happened: `run.sh` built `test.mod`, checked every script in it compiled (the same check as step 6), and
started two containers from `tests/compose.yaml`: the NWNX image named in your compile check, and a MariaDB whose
data lives only in memory. As the module loaded, NWNX ran a few words of script set in the Compose file, which
starts the runner (`t_boot`, then `t_runner`). The runner found every compiled script named `t_<system>_<case>`,
ran each one, wrote a line to the server's log for each result, and wrote a last line when it was done. `run.sh`
waited for that line, copied the logs out, stopped both containers and threw them away.

Everything the run left is in `tests/.run/`: `logs/nwserverLog1.txt` (the server's log, with every `TEST|` line),
`logs/nwengineLog.txt` (the engine's own log, where script errors go), and `junit.xml`, a standard test report
that GitHub and most tools can read.

Two of the examples are worth a look. `t_db_roundtrip` writes to the database and reads it back through NWNX_SQL,
so it proves the plugin, the settings and the database all work together. `t_load_recorded` checks the row your
`mod_load` script from step 5 wrote when the module loaded: a test of your own module's code, on a real server.

#### 14. GENERIC. Write a test of your own

A test is a script in `tests/nss`, named `t_` then the system it tests, an underscore, and the case, at most 16
characters in all. It includes `inc_test`, does something, and checks the result:

```c
// t_chest_empty: a chest made from the game's own blueprint starts empty.
#include "inc_test"

void main()
{
    object oChest = CreateObject(OBJECT_TYPE_PLACEABLE, "plc_chest1", GetStartingLocation());
    Assert(GetIsObjectValid(oChest), "the chest was made");
    Assert(!GetIsObjectValid(GetFirstItemInInventory(oChest)), "it holds nothing");
    DestroyObject(oChest);
}
```

The rules are short:

- A test passes when it made at least one assert and none failed. A test that makes no assert at all fails, on
  purpose: that is also what a test looks like when it stopped half-way on a script error.
- `Assert`, `AssertInt` and `AssertStr` each say what should be true. When one fails, the log shows its words and
  what it got: `arithmetic: got 4, want 5`.
- A test that must wait for the game, such as a `DelayCommand`, calls `Test_Async()` first and `Test_Done()` when
  it has checked everything. `t_delay_async` is the example. If `Test_Done()` never comes, the test fails after its
  timeout (10 seconds unless you give another).
- A test that can't run in this module calls `Test_Skip("why")` and returns.
- Tidy up after yourself: destroy what you made, drop the tables you created. Tests run one after another on the
  same server, so a mess left by one is the next one's problem.

To run just one system's tests while you work on it:

```sh
tests/run.sh --filter t_chest_
```

#### 15. GENERIC. Watch a test fail, twice

As with the compile check, see it fail before you trust it. A wrong answer:

```sh
printf '#include "inc_test"\nvoid main()\n{\n    AssertInt(2 + 2, 5, "arithmetic");\n}\n' > tests/nss/t_math_wrong.nss
tests/run.sh --filter t_math_; echo "exit status $?"
```

```
FAIL  t_math_wrong  (arithmetic: got 4, want 5; 1 of 1 asserts failed)
0 passed, 1 failed, 0 skipped
exit status 1
```

And a script that stops on an error. The game doesn't tell the script that called it; it writes the error to the
engine's log and carries on. `results.py` reads that log too:

```sh
printf '#include "inc_test"\nvoid main()\n{\n    Assert(TRUE, "fine so far");\n    int n = 1 / GetLocalInt(OBJECT_SELF, "zero");\n}\n' > tests/nss/t_math_divide.nss
tests/run.sh --filter t_math_; echo "exit status $?"
```

```
FAIL  t_math_divide  (script error: DIVIDE BY ZERO)
FAIL  t_math_wrong  (arithmetic: got 4, want 5; 1 of 1 asserts failed)
0 passed, 2 failed, 0 skipped
exit status 1
```

The first assert in `t_math_divide` passed, so without reading the engine's log this test would have passed. That
is the reason the check reads both logs. A script error in any of your module's scripts during the run, not only in
a test, fails the run too, as "the run itself".

Take both out again: `rm tests/nss/t_math_*.nss`.

#### 16. ADAPT. Give the test server what your live server has

Change: the plugins, and the haks and talk table if you have them.

The test server should be your live server's twin, minus anything that talks to the outside world. Open
`tests/compose.yaml`: under `nwserver`, `environment` switches on Util (the runner needs it) and SQL. Add every
`NWNX_..._SKIP=n` line your live `.env` has, except plugins that send things out (webhooks, metrics), which have
nowhere to go on a network with no route out anyway.

If your module uses haks and a talk table (chapter 7), point the test server at them:

```sh
TEST_HAK_DIR=~/mycontent/build/hak TEST_TLK_DIR=~/mycontent/build/tlk tests/run.sh
```

The image is the one named in your compile check's `NWNX_IMAGE`, so tests and check always agree. When you move to
a new NWNX version, change it in `compile-check.yml`, `tests.yml` and `release.yml` together; I'll admit three
places is two too many, but it keeps each workflow readable on its own.

#### 17. GENERIC. Tests on every pull request

Commit the new files and push. From then on `tests.yml` runs on every pull request and every change to `main`,
beside the compile check:

```sh
git add -A && git commit -m "Tests that run on a real server"
git push
```

On the test it took under a minute. The run's page shows the results in its summary, and under **Artifacts**,
`test-logs` holds the same `tests/.run/` folder you get at home, kept for 14 days, failed runs included. That is the
first place to look when a test fails on GitHub and not at home.

To make a red test block a merge: in the repository's **Settings**, **Rules**, **Rulesets**, add a rule for the
default branch that requires the status checks `compile` and `tests`. Rulesets are free on public repositories;
on a private one they need a paid GitHub plan.

A pull request with the failing test from step 15 failed on the test, with `FAIL  t_math_wrong` in its log; the
compile check beside it stayed green, as it should, because everything compiled. With the ruleset on, GitHub
refused to merge it.

#### 18. ADAPT. The staging copy

Change: the folders, if your deploy user isn't `nwn`; the port, if 5122 is taken.

Staging is a second game on the game host, built from the same image, on port 5122, with folders of its own in
`~/staging`. It never shares anything with the live game except the machine.

On the game host:

```sh
ssh nwn@GAME 'mkdir -p ~/staging/home/modules ~/staging/db ~/staging/logs'
scp templates/game/stage.sh nwn@GAME:staging/
```

Then open UDP 5122 in your provider's firewall, beside 5121 (chapter 1, step 3). That is the firewall that
counts here: Docker opens the ports it publishes past `ufw`, as chapter 1's step 6 showed. If you'd rather only
your testers could reach staging, allow 5122 from their addresses only.

In Coolify, in the `game` project, add a resource: **Docker Compose**, on the game host, and paste
[`templates/game/staging.yaml`](../templates/game/staging.yaml). Give it these settings in **Environment
variables** (**Developer View** takes them as lines):

```
NWNX_IMAGE=nwnxee/unified:ed79330
NWN_MODULE=mymodule
NWN_SERVERNAME=My server (staging)
NWN_PUBLICSERVER=0
NWN_PLAYERPASSWORD=a password for your testers
NWN_DMPASSWORD=a new one, not the live one
NWN_ADMINPASSWORD=a new one, not the live one
NWNX_SQL_PASSWORD=a new one, not the live one
NWNX_SQL_SKIP=n
NWNX_SQL_TYPE=mysql
NWNX_SQL_DATABASE=nwn
NWNX_SQL_USERNAME=nwn
NWNX_UTIL_SKIP=n
```

plus the same `NWNX_..._SKIP` lines as the live game, and any other `NWN_` setting you changed for live, such as
`NWN_MAXCLIENTS`. `NWN_MODULE` is the module's name, the same as live: staging
loads whatever file of that name `stage.sh` gives it. Passwords of its own mean that a staging password that leaks
opens nothing live. Then **Deploy**.

The services in `staging.yaml` are called `staging-nwserver` and `staging-mariadb`, not `nwserver` and `mariadb`.
That matters: `backup.sh` and `release.sh` find the live game by those plain names, and with two of each they would
stop, rightly unsure which one you meant. I checked: with staging running, both still found the live game.

The first deploy starts a game with no module of its own yet, so it keeps restarting until the first stage. That's
expected, and it is the next thing to fix. Do it by hand once, with the module from your latest compile check:

```sh
scp mymodule.mod nwn@GAME:
ssh nwn@GAME 'sudo staging/stage.sh "stage v0.0.1" < mymodule.mod'
```

```
received v0.0.1: 39126 bytes, sha256 ...
staging game stopped
staging database filled from ../game/backups/20261126-030000
staging characters copied from ../game/backups/20261126-030000
staging game started with mymodule.mod
staging is healthy with v0.0.1
```

Every stage does the same: empties the staging database and fills it from the live game's latest nightly backup,
copies the character vault from it, puts the module in place and waits until the game answers. So staging always
plays with yesterday's world, and nothing a tester does there survives the next release. It reads the live game's
backups and touches nothing else of it.

From your own computer, `templates/game/nwn-status.py GAME 5122` should now answer with `module mymodule`.

#### 19. GENERIC. A key that can only stage

GitHub will log in to your game host to stage releases, so it needs a key. Make one that can do that and nothing
else. On your own computer:

```sh
ssh-keygen -t ed25519 -N '' -C staging-from-github -f ~/.ssh/mymodule-staging
```

Put its public half on the game host with a fixed command in front of it:

```sh
{ printf 'command="sudo -n /home/nwn/staging/stage.sh \\"$SSH_ORIGINAL_COMMAND\\"",restrict '; cat ~/.ssh/mymodule-staging.pub; } \
  | ssh nwn@GAME 'cat >> ~/.ssh/authorized_keys'
```

`command=` means: whatever a login with this key asks for, run `stage.sh` instead, and hand it the request to
check. `restrict` switches off everything else a login could do: no shell, no port forwarding, no file copying.
Try it:

```sh
ssh -i ~/.ssh/mymodule-staging nwn@GAME "stage v0.0.2" < mymodule.mod | tail -1
ssh -i ~/.ssh/mymodule-staging nwn@GAME 'cat /etc/passwd'
```

The first stages again and ends with `staging is healthy with v0.0.2`. The second is refused by `stage.sh` with
`usage: stage vX.Y.Z`, and that's the point: someone who stole this key could put a module on staging, and no
more.

#### 20. GENERIC. The staging environment on GitHub

GitHub keeps secrets for a workflow in **environments**: a named place, here `staging`, with its own secrets and
its own rules about who may use them. In the module repository's **Settings**, **Environments**, **New
environment**, name it `staging`, and:

- under **Deployment branches and tags**, choose **Selected branches and tags** and add a rule for tags named
  `v*`. Only a release tag can then reach the key; a branch, or a pull request, cannot;
- add the secret `STAGING_SSH_KEY`: the whole private key, `~/.ssh/mymodule-staging`, pasted in;
- add the variable `STAGING_HOST`: the game host's address;
- add the variable `STAGING_KNOWN_HOSTS`: the game host's own key, so the workflow knows it is talking to your
  machine. Get it with `ssh-keyscan -t ed25519 GAME` and compare it with what your own `~/.ssh/known_hosts` says
  for that machine before you paste it.

Variables are visible to anyone who can read the repository; secrets are not, and GitHub blanks them out of logs.
The address and the host key aren't secret, so they're variables, which makes them easy to check later.

Then delete the private key from your computer, or keep it in your password manager. GitHub has it now, and you
can always make a new one.

#### 21. GENERIC. Release by tag

When `main` holds what you want to release:

```sh
git checkout main && git pull
git tag -a v0.2.0 -m "v0.2.0"
git push origin v0.2.0
```

That starts `release.yml`, whose three jobs you can watch under **Actions**:

1. **tests**: the whole of `tests.yml`, on the tagged commit. If a test fails, nothing else happens.
2. **release**: builds the module, runs the compile check's second pair of eyes over it, and makes a GitHub release
   named after the tag with `mymodule.mod` and its checksum attached, and notes listing the pull requests since the
   last release.
3. **staging**: downloads that release's file, checks the checksum, and sends it to `stage.sh` with the key from
   step 19.

On the test it took 1 minute 53 seconds from the push to `staging is healthy with v0.2.0` at the end of the last job's
log. A tag is a promise that a version is one exact thing, which is why the release keeps the file itself: months
later you can still download exactly what `v0.2.0` was.

`git tag -a` makes an annotated tag, with a message of its own. Some git setups refuse a plain `git tag v0.2.0`
with "no tag message"; `-a` and `-m` work everywhere.

#### 22. GENERIC. Try it, then go live

Connect to staging with your game client, on the game host's address and port 5122, with the testers' password.
Try the release's main change. Ask a builder or two to look too. This is the moment a release was made for.

When you're happy, the module on staging is the one that goes live, byte for byte. On the game host:

```sh
cat ~/staging/staged.txt
mkdir -p ~/incoming
sudo cp ~/staging/home/modules/mymodule.mod ~/incoming/
cd ~/game && sudo ./release.sh
```

`staged.txt` says which version is on staging and its checksum, which you can compare with the release's
`SHA256SUMS`. `release.sh` is chapter 16's, unchanged: backup, keep the old module, swap, wait until healthy, and
`--undo` to go back. Chapter 16's checklist still applies around it. Going live stays a person's step on purpose:
the workflow holds a key to staging only, and nothing on GitHub can restart your live game.

If staging shows a problem: fix it in a pull request, merge, tag `v0.2.1`. Staging gets the new version and a
fresh copy of the world; live never saw the old one.

#### 23. LAYONARA-ONLY. Fake players and leftovers

Our runner does three things this template doesn't. It can attach fake players, so a test can walk a character
through a door or a conversation; that needs a plugin that is in our own NWNX build only, so the template leaves it
out. It fails a test for anything it left behind in the world. And it waits, before the first test, until every
creature placed in the areas has finished its own start-up scripts, because on a busy machine a creature's loot
being made during the first test was once blamed on that test. With five hundred tests each of these earned its
place. With ten, you won't miss them.

### The agent playbook

If you work with an AI agent, [`playbooks/06-module-tier2.md`](../playbooks/06-module-tier2.md) has these steps in
a fixed shape. It stops and asks before it creates the staging service, before it adds a key to the game host, and
before every tag; going live is always yours.

### Lessons

- **A step that pipes into `tee` can hide a failure.** My first test workflow ran `tests/run.sh | tee results.txt`.
  A pull request with a failing test came back green: GitHub's default shell takes the exit status of the last
  command in a pipe, which was `tee`, which was happy. The step now starts with `set -o pipefail`, and the same pull
  request turned red.
- **A script error doesn't stop the script that called it.** The runner calls each test with `ExecuteScript`. When
  the test divides by zero, the game logs the error in the engine's log, ends that test, and the runner carries on
  none the wiser. A test that made one good assert before its error would pass. That is why `results.py` reads the
  engine's log too, and why a test with no asserts at all fails.
- **Never let a run that didn't finish look like a pass.** If the server crashes or hangs, there is no last line in
  the log. `results.py` counts that as a failure of the run itself, and `run.sh` gives up after ten minutes, so a
  hung server costs ten minutes, not GitHub's limit of six hours.
- **Keep staging's name apart from live's.** Two services both called `nwserver` on one machine and the backup
  script, rightly, refuses to guess. Different names cost nothing.
- **Stage the file you will release.** A rebuild "of the same commit" for going live can differ (another nasher,
  another day). Staging the release's own file, and going live with the file staging ran, means what players get is
  exactly what you tried.

### Tested

On 2026-11-26, with nasher 1.2.2, neverwinter.nim 2.3.2, `nwnxee/unified:ed79330`, MariaDB 11.8 and Coolify 4.7.5,
using the tier 1 demo module with chapter 6's `mod_load` example:

- `tests/run.sh` at home with Docker 29.1: all four example tests passing (17 to 20 s each run), `--filter`,
  `--no-build`, a skipped test, a wrong assert, a division by zero (caught from the engine's log), a test that
  never called `Test_Done()`, and a run that didn't finish in time; each failure gave exit status 1;
- the same on GitHub's machines in a private throwaway repository: a passing run on `main` (58 s in all), a pull
  request with a failing test (red, after the `pipefail` fix in the lessons), and the logs kept as an artifact;
- a tag making a release with `mymodule.mod` and `SHA256SUMS` attached, and the same run putting that file on
  staging with the key from the environment: 1 minute 53 seconds from the push to a healthy staging game, the
  secret blanked in the log, and the checksum in `staged.txt` the same as the release's;
- the staging copy as a second Coolify service beside the live one (itself moved into Coolify with chapter 4's
  tier 2 playbook), a stage taking about 8 seconds on a cx23;
- the forced-command key: staging by hand with it, and every other command, a port forward and `scp` refused;
- a tag on a commit with a failing test: the tests job failed, and the release and staging jobs were skipped, so no
  release was made and staging kept the version it had;
- the ruleset: with `compile` and `tests` required, the pull request with the failing test could not be merged;
- the `staging` environment: a job on a branch was refused it ("not allowed to deploy to staging due to
  environment protection rules"), a job on a tag got it;
- going live with staging's file through chapter 16's `release.sh`, and `backup.sh` and `release.sh` still finding
  the live game with staging running;
- this chapter's agent playbook from step 6 on, as written, against the same repository and servers.

Not tested: a module with haks in the test server (`TEST_HAK_DIR`), a real tester connecting to staging with a game
client (the status query answered instead).
