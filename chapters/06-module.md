# Chapter 6. Your module in git

**Status:** tiers 1, 2 and 3 are written and tested.

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
- the same tests on GitHub's machines on every pull request, with the logs kept for each run, and with your haks
  and talk table downloaded from your own download address, as a player's game would;
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
- **The tests get the real haks.** Our tests run on our own machines, beside a copy of the haks our build
  publishes, and each run takes a snapshot of that copy, so a build finishing half-way through a run can't change
  the haks under a test. Here I suggest the simpler way for GitHub's machines: download them from your own address.
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
printf 'tests/.run/\ntests/.content/\n' >> ~/mymodule/.gitignore
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

Change: the plugins; and your download address, if your module uses haks.

The test server should be your live server's twin, minus anything that talks to the outside world. Open
`tests/compose.yaml`: under `nwserver`, `environment` switches on Util (the runner needs it) and SQL. Add every
`NWNX_..._SKIP=n` line your live `.env` has, except plugins that send things out (webhooks, metrics), which have
nowhere to go on a network with no route out anyway.

**Haks and the talk table.** If your module lists haks (chapter 7), the test server needs them as much as the live
one does. Without them it stops at once with `Unable to load module`, and says nothing about why. So `run.sh`
checks first and names what's missing:

```
the module needs my_first_hak.hak, and the test server has no .../tests/.run/hak/my_first_hak.hak
the module needs my_tlk.tlk, and the test server has no .../tests/.run/tlk/my_tlk.tlk
give it your content with --content (chapter 6, step 16); if this change needs new content, stage it first
the test server would not load this module
```

The simplest honest place to get them is the one your players use: your download address. A player's game
downloads the content your game hands out, file by file, and the tests can do exactly the same:

```sh
tests/run.sh --content https://nwsync.example.org
```

```
content b8311026bbed059ac36f81b2f6fb8bb861ab93f5: 3 files checked, 2 haks, 1 talk tables
server ran for 14 s
PASS  t_content_hak
...
```

[`tests/tools/fetch_content.sh`](../templates/module/tests/tools/fetch_content.sh) downloads every file over HTTPS,
checks each one against its checksum, and packs them back into the haks they came from, in `tests/.content`. The
address is public, so there's no secret to keep. Three things to know:

- **Which version.** If chapter 7's tier 2 has staged new content (it puts it under `/staging` on your address for
  the staging copy, step 18), the tests use that, because it is what your next release will carry. Otherwise they
  use what players get now. Either way the first line says which.
- **It needs a list of which hak each file came from.** A download by itself only knows files. Chapter 7 writes
  that list (`--write-origins`, a small file beside each version) from this section on. If your content was written
  before, publish it once more: the same content gives the same version, so players download nothing new.
- **Script sources aren't there.** The download leaves out `.nss` files, which players never need. The server
  doesn't either: it runs the compiled ones.

A test that proves the content is really loaded is worth its few lines. Mine reads a line from the example hak's
table and one from the talk table:

```c
// t_content_hak: the haks and the talk table the live game hands out are loaded.
#include "inc_test"

void main()
{
    AssertStr(Get2DAString("ex_notes", "Note", 0), "Packed from a folder in git", "a table from my_first_hak");
    AssertStr(GetStringByStrRef(16777216), "This line comes from my own talk table.", "a line from my_tlk");
}
```

On GitHub, set your address once, in `tests.yml`:

```yaml
  NWSYNC_URL: "https://nwsync.example.org"
```

Each run then asks your address which version to use, and downloads it only if GitHub's cache doesn't already
have it (chapter 8, step 3). A version's name is the checksum of its list of files, so a cached one can't be stale.

**A change that needs new content.** Say a pull request adds a hak to the module's list. Its tests fail with
`the module needs my_second_hak.hak`, and that's right: nothing has that hak yet. Stage the content first, with
chapter 7's `publish.sh` (its step 21), then press **Re-run jobs** on the pull request. The run now takes the
staged version, and passes. On the test it did exactly that. Testing a content repository's own pull requests,
before anything is published, is beyond this tier.

If you build your content at home and want to test with that instead of what's published, point at the folders:

```sh
TEST_HAK_DIR=~/myhaks/build/hak TEST_TLK_DIR=~/myhaks/build/tlk tests/run.sh
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
`test-logs-lane-1` holds the same `tests/.run/` folder you get at home, kept for 14 days, failed runs included.
That is the first place to look when a test fails on GitHub and not at home.

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

If your module uses haks, staging needs them too, and it gets them the same way as the tests: chapter 7's
`publish.sh`, in tier 2, gives staging the content it stages, and chapter 16's step 12 has the one setting staging
needs for that. Until then, a module that lists haks can't start on staging. The tests take that same staged
version (step 16), so what passes on GitHub is what staging plays.

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
- **A module with haks can't load without them.** The first version of these tests passed on a module with no
  haks, and stopped with `Unable to load module` on one that had them, because nothing gave the test server any.
  The download address already hands out exactly the content the live game uses, checksummed, to anyone; the
  tests now take it from there, and `run.sh` names a missing hak instead of leaving you to guess.
- **The download alone doesn't know its haks.** It lists files, not which hak each came from, and a module names
  haks. The NWSync writer can keep that list (`--write-origins`); chapter 7 now asks it to.
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

The haks and talk table for the tests (step 16, and the note in step 18) were tested on 2026-11-26 with the same
versions, on a pair of fresh Hetzner cloud servers of the smallest shared type brought to chapter 7's tier 2 state:
the downloads service in Coolify on the control host under a temporary name in our own domain, with a real
certificate, the example content published and promoted with `publish.sh` and `promote.sh` (now with
`--write-origins`), and the game handing it out. The staging copy was a `~/staging` folder that `publish.sh` fed;
no staging game ran (chapter 16's tier 2 tested that one). A private throwaway repository made from the template,
with a module that lists the example hak and talk table and the content test above:

- with no address set, a run on GitHub failing before the server started, naming the hak and the talk table;
- with the address set, a run on `main` downloading the version (2 files, about 2 s), saving it in the cache and
  passing, and a second run restoring it from the cache and skipping the download;
- a pull request adding a second hak: failing with `the module needs my_second_hak.hak`, then, after `publish.sh`
  staged the new content, the same run re-run and passing with the staged version;
- a release tag running the tests with the staged content and making its release; a tag on a module needing a
  hak nobody had published failing at the tests, with no release made;
- the downloads service stopped: the run failing at its first content step with `could not read
  https://.../staging/latest (HTTP 503): is the download address up?`;
- at home: `--content` against a local copy, the talk table rebuilt byte for byte and the hak with the same file
  in it, and a version without its list refused with a message saying what to do.

Not tested: content big enough for the cache's 10 GB limit, and a pull request from a fork.

Not tested, from the first round: a real tester connecting to staging with a game
client (the status query answered instead).

## Tier 3. Choosing tests, lanes, and flaky tests kept honest

### What you learn

What to do when your test suite has grown from ten tests to a few hundred, and a run that took a minute now takes
half an hour. Three things, each adopted on its own, in this order:

- **Test selection.** A pull request runs only the tests its change can affect. Every night, and before every
  release, everything runs anyway.
- **Lanes.** The tests a run needs are dealt out to several servers at once, each with its own database, so the
  wait is a third or a quarter of what it was.
- **Flake control.** A test that fails is run once more on a fresh server. If it passes then, the run passes but
  says so loudly, and writes it down. A test that keeps doing that goes on a short quarantine list with an issue
  number, and a report every morning shows both, so a flaky test is never quietly forgotten.

When you're done, you'll have:

- `tests/tools/plan.py`, which reads a change and says which tests can reach it, and deals them into lanes;
- the tests workflow running a pull request's tests only, in up to three lanes, with one job at the end, `tests`,
  that is green only when every lane is;
- the whole suite every night, by hand, and as the first step of every release;
- a retry on a fresh server, and a record of every test that needed it;
- `tests/quarantine.txt`, and a flake report on GitHub every morning.

None of this changes how a test is written, or how `tests/run.sh` runs at home. It's all about choosing what to
run, and where.

**Time:** about half an hour, most of it reading what the planner says about your own module. Chapter 8's tier
3 moves these runs onto your own machines; this section works on GitHub's machines as well.

You need chapter 6's tier 2 (the tests on every pull request). Come here when the tests take long enough that
people start to wait for them, or to skip them. Before then, running everything every time is simpler and right.

### What Layonara does

- **About five hundred tests, and a night to run them all.** The whole suite takes about 27 minutes of server time.
  That is fine at night and too long for every push to a pull request.
- **A pull request runs what its change can reach.** A planner reads the change and maps it to tests: through
  includes, script names in strings, blueprints and dialogs that name a script, the game's spell table, and the
  tables a database migration touches. A change to shared code, or to the test harness itself, runs everything; a
  change that no test reaches still builds the module and starts it; a change outside the module runs nothing.
- **Everything, every night.** The nightly run takes every test, slow soak tests included, and a label on a pull
  request asks for everything before a risky merge.
- **New tests are tried five times.** A test a pull request adds or changes runs five times in a row on a second
  server, with no retry, before it is trusted. It's the cheapest moment to find out a test is flaky: before it is
  anyone else's problem.
- **One retry, and it's written down.** A test that fails (at most five of them) runs once more on a fresh
  server. A pass there is "flaky": the run passes, warns, and writes a line to a flake log.
- **Lanes, on our own machine.** Three lanes, each with a fixed share of the cores and memory, so a test run never
  slows the rest of the machine. Chapter 8's tier 3 has the machine side.
- **No quarantine list.** Our record is the retry's flake log and the five tries above. The quarantine list here
  is my suggestion for a team that can't fix every flaky test the day it shows up, which is most teams.

### The human playbook

The files are in [`templates/module`](../templates/module): `tests/tools/plan.py`, `tests/tools/flake_report.py`,
`tests/quarantine.txt`, the new `tests/run.sh`, `tests/tools/results.py` and `tests/nss/t_runner.nss`, and the
workflows `.github/workflows/tests.yml` and `.github/workflows/flake-report.yml`.

#### 24. GENERIC. Bring the new files in

If you made your repository from the template after this section existed, you have everything. Otherwise:

```sh
cd ~/mymodule
cp ~/nwn-server-playbook/templates/module/tests/run.sh tests/
cp ~/nwn-server-playbook/templates/module/tests/nss/t_runner.nss tests/nss/
cp ~/nwn-server-playbook/templates/module/tests/tools/{plan.py,results.py,flake_report.py} tests/tools/
cp ~/nwn-server-playbook/templates/module/tests/quarantine.txt tests/
cp ~/nwn-server-playbook/templates/module/.github/workflows/{tests.yml,flake-report.yml} .github/workflows/
```

If you changed your own `tests.yml` (your download address, your image), put those changes back into the new
one: it has the same settings at the top, plus four more.

Two things changed in how the runner reads `--filter`, and both are backwards-compatible: it now takes a list,
separated by commas, and an entry that doesn't end in an underscore is one test's whole name:

```sh
tests/run.sh --filter t_bank_,t_math_add
```

runs every `t_bank_` test and the one test `t_math_add`. That is how the planner hands a lane its exact list.

#### 25. GENERIC. See what a change reaches

At home, on a branch with a change in it:

```sh
python3 tests/tools/plan.py --base main
```

On the test, with a small bank, a greeting and a shop beside the template's examples (18 tests), a change to the
greeting's include file said:

```
select: 2 files changed: 3 of 18 tests reach them
lane 1: t_greet_evening,t_greet_morning,t_greet_noon
```

What it does, in plain words. For every test it follows the `#include` lines, all the way down, and collects every
word that appears inside quotes in those scripts: `ExecuteScript("shop_restock")`, a blueprint's name in
`CreateObject`, a table's name in an SQL string, a tag. Then it takes the files your change touched, and grows
that list through your module: a script that includes a changed script has changed too, and so has a blueprint,
area or dialog whose fields name one. A test runs when anything it reaches is on that list.

Four answers, and what each means:

| Mode | When | What runs |
|---|---|---|
| `select` | the change reaches some tests | those tests |
| `full` | the test harness, the workflows, `nasher.cfg` or `module.ifo` changed, or there is no base | every test |
| `boot` | the module changed, but no test reaches the change | the module is built and started, no test runs |
| `none` | nothing the test module is made of changed (notes, migrations, other folders) | nothing at all |

`boot` matters more than it looks. A change to a script that only runs as the module loads, such as your own
`mod_load`, can still stop the module from starting. Building and starting it costs twenty seconds and catches
that.

Try a few of your own changes and read what it says. It errs on the side of running a test: a word in quotes that
only looks like a file's name runs that test too. On the test, the word `start` in one test's message ("the start
area") made it run whenever the area named `start` changed, which happened to be right. What it can't see is a
name your script puts together while it runs (`"bank_" + sKind`). The nightly run of everything is the net for
that, and for anything else it misses.

#### 26. GENERIC. Switch it on

At the top of `tests.yml`:

```yaml
  TEST_SELECT: "true"
  TEST_LANES: "3"
  TEST_LANE_LEAST: "4"
  TEST_RETRY: "true"
```

`TEST_SELECT` turns on step 25 for pull requests. Every other run, a push to `main`, a run by hand, the nightly
run and the run inside every release, still takes every test. `TEST_LANES` and `TEST_LANE_LEAST` are step 27;
`TEST_RETRY` is step 28. Each works without the others; I'd switch them on one at a time, in this order, and watch
a few pull requests after each.

The workflow now has three kinds of job:

1. **plan**, which runs `plan.py` and shows its answer at the top of the run's page;
2. **lane 1**, **lane 2**, **lane 3**: one job each, each with its own test server and database;
3. **tests**, which gathers the lanes and is green only when all of them are, or when no lane was needed.

Keep `tests` as the required check in your ruleset (chapter 6, step 17): it has the same name as the old single
job, so nothing changes there. A pull request that changes only notes shows `plan` and `tests` green and the lanes
skipped, which is exactly right, and it can merge.

The nightly run is the `schedule` line at the top of `tests.yml`, at 03:17 UTC; change the time to your quiet
hours. GitHub runs scheduled workflows only from the default branch, and in a public repository it stops them after
60 days without any activity; a repository you work in never gets there.

#### 27. GENERIC. Lanes

`plan.py --lanes 3` deals the tests out like cards, so each lane gets the same number, give or take one. It never
makes a lane of fewer than `TEST_LANE_LEAST` tests: starting a server takes about twelve seconds, so three lanes of
one test each would spend most of their time starting. On the test, eighteen tests made three lanes of six, and a
pull request that reached three tests made one lane.

```sh
python3 tests/tools/plan.py --lanes 3
```

```
full: no base to compare with: every test
lane 1: t_area_start,t_bank_overdraw,t_delay_async,t_greet_morning,t_math_add,t_shop_restock
lane 2: t_bank_deposit,t_bank_withdraw,t_flaky_coin,t_greet_noon,t_math_mul,t_shop_twice
lane 3: t_bank_negative,t_db_roundtrip,t_greet_evening,t_load_recorded,t_module_start,t_shop_untouched
```

To run one lane at home, exactly as the workflow does, give its list to `--filter`.

Be honest with yourself about the numbers. On GitHub's machines, each lane is a whole job: a fresh machine, the
tools installed, the image pulled. On the test that was about 25 seconds a lane before the first test ran, so for
eighteen tests three lanes saved nothing. Lanes pay when the server time is minutes, not seconds: a suite that
takes half an hour on one server takes about ten minutes on three. Each lane
also uses its own GitHub minutes, which is one more reason chapter 8's tier 3 moves them to your own machine.

A lane deals by name, not by how long each test takes. If one lane is always much slower, that's the next thing to
improve, and the honest first step is to look at which tests are slow, not to make the dealing cleverer.

#### 28. GENERIC. One retry, written down

With `TEST_RETRY`, `run.sh --retry` runs again, once, on a fresh server and database, every test that failed, as
long as there are at most five of them. More than five is not bad luck; that's something broken, and the run fails
straight away. A crash of the server isn't retried either. What a second try can show:

```
failed: t_shop_untouched; running them once more, on a fresh server
server ran for 11 s
PASS  t_shop_restock
PASS  t_shop_twice
FLAKY  t_shop_untouched  (failed, then passed on a fresh server; the first time: no restock has happened yet: got 3, want 0; ...)
3 passed (1 of them only on a second try), 0 failed, 0 skipped
WARNING: 1 test(s) passed only on a second try. ...
```

That one was a real lesson in miniature. `t_shop_untouched` expected that no restock had happened yet. Run after
the other two shop tests, it found three; run on its own, on a fresh server, it passed. So the run passed, which
is right (the code is fine), and said FLAKY, which is also right (the test depends on what ran before it). The fix
is in the test: count from where it starts, as `t_shop_restock` does.

Every FLAKY result is written to `tests/.run/flakes.jsonl`: the test, why it failed the first time, the commit,
the run and the lane. The workflow gathers every lane's lines into one artifact called `flakes`, kept for 30 days,
and shows them on the run's page.

Why retry at all, after chapter 8 said not to in tier 2? Because with a few hundred tests on shared machines, an
occasional failure that has nothing to do with the change becomes a weekly event, and people learn to press
**Re-run** without reading. A retry that is automatic, on a fresh server, limited to five tests, and written down
every time keeps the run's colour honest and makes the flake visible, not hidden.

#### 29. GENERIC. The quarantine list

Sometimes a test is flaky and the fix isn't quick. Switching it off loses it; leaving it in makes everyone's
runs red. The middle way is `tests/quarantine.txt`:

```
t_flaky_coin   # issue 1, 2026-11-26: fails one time in two
```

A test on the list still runs every time. When it fails, the run reports it as `QUARANTINED` and doesn't fail for
it, and the failure is written down like a flaky one; when it passes, the line says so, as a reminder that it may
be ready to come off:

```
QUARANTINED  t_flaky_coin  (failed, and is quarantined: the coin came up heads: got 1, want 0; ...)
5 passed, 0 failed, 0 skipped, 1 failed in quarantine
```

My rules for the list, written at its top: one test a line, always with an issue number and the date, and short.
A list that grows is a suite that is quietly shrinking. A pull request that adds or removes a line runs that test,
so you see what the change means before it's merged.

#### 30. GENERIC. The flake report

`flake-report.yml` runs every morning at 04:47 UTC, after the nightly tests, and by hand from **Actions**. It
downloads every `flakes` record of the last two weeks and writes a report on its run's page:

```
## Flake report: the last 14 days

| Test | Flaky | Failed in quarantine | Last seen | Last reason |
|---|---|---|---|---|
| `t_flaky_coin` | 0 | 2 | 2026-11-26 | failed, and is quarantined: the coin came up heads: got 1, want 0; ... |
| `t_shop_untouched` | 1 | 0 | 2026-11-26 | failed, then passed on a fresh server; the first time: no restock ... |

### The quarantine list

- `t_flaky_coin`, on the list for 0 days: still fails (2 times) (issue 1, 2026-11-26: fails one time in two)
```

It changes nothing; it is a page to read once a week, ideally with the person who looks after the tests. The same
report at home, from a folder of records you downloaded:

```sh
python3 tests/tools/flake_report.py --days 14 records/
```

#### 31. LAYONARA-ONLY. Five tries for a new test, slow tests at night

Two more ideas from our suite that I left out of the template. A test that a pull request adds or changes runs five
times in a row on a second server before the pull request can merge, which finds most flaky tests before they
exist for anyone else. And about eight long soak tests run only at night, listed in a file of their own. Both are
worth adding once your suite is big enough to make you want them; the planner's `select` list is where the five
tries would start.

### The agent playbook

If you work with an AI agent, [`playbooks/06-module-tier3.md`](../playbooks/06-module-tier3.md) has these steps in
a fixed shape. It checks what the planner says before anything is switched on, stops and asks before it changes
the workflow's settings, and never adds a test to the quarantine list or takes one off: that is always a person's
call, with an issue number.

### Lessons

- **A hidden folder isn't uploaded.** `actions/upload-artifact` leaves out hidden files and folders unless it is
  told `include-hidden-files: true`, and `tests/.run` starts with a dot. So from tier 2 on, the "test-logs"
  artifact quietly held nothing, and it took the flake report, which reads the records in that folder, finding
  none to notice. The workflow now says `include-hidden-files: true`, and the test now checks the record arrives,
  not only that the step was green.
- **A run by hand stopped the push it shared a branch with.** The tier 2 workflow stopped an older run whenever a
  newer one started on the same branch. With a nightly run and runs by hand, that meant a run by hand on `main`
  cancelled the push run beside it. Now only a pull request's older run is stopped, and runs of different kinds
  each finish.
- **A test that passes alone and fails in company isn't random.** The retry runs failed tests on their own, so a
  test that depends on what ran before it shows up as FLAKY every time it shares a lane with the wrong neighbour.
  Three of our own flaky tests were exactly this: they failed because of what an earlier test left behind. We
  fixed them by making each test start from where things stand, never from a count it assumes, and then added a
  check for anything a test leaves behind.
- **The planner errs towards running.** A missed test is a bug that reaches players; an extra test is twenty
  seconds. Every rule in `plan.py` that could go either way runs the test.

### Tested

On 2026-11-26, with the versions of tier 2 (nasher 1.2.2, neverwinter.nim 2.3.2, `nwnxee/unified:ed79330`, MariaDB
11.8), in a private throwaway repository made from the module template with the demo module, a small bank, a
greeting and a shop: 18 tests, one of them deliberately flaky and quarantined, one that depends on what ran before
it.

- `plan.py` at home on nine kinds of change: an include (3 tests), a script reached only by name in a string (2),
  an area (2), the module's load script (2), one test (1), the quarantine list (the test named), notes only
  (`none`), the test harness (`full`), and the NWNX include (3);
- `run.sh` at home: a list filter of whole names and prefixes, `--boot-only`, a list of 600 names (9,010
  characters) passed to the server in one go, `--retry` (a flaky test reported FLAKY, a broken one failing twice),
  and a quarantined test (QUARANTINED, exit 0);
- on GitHub's machines: a push running all 18 tests in three lanes of six, 1 minute 9 seconds in all, the
  quarantined test failing without failing the run;
- on our own runners (chapter 8, tier 3): a pull request changing the greeting (one lane, 3 tests), one changing
  an area (one lane, 2 tests), and one changing only notes (no lanes, `tests` green); a run by hand of the shop
  tests making `t_shop_untouched` FLAKY with its record in the `flakes` artifact; the nightly path (a run by hand
  of everything) in three lanes; the flake report listing the flaky and the quarantined test;
- the two lessons above, each found on the test and checked again after the fix;
- the template's own settings (tier 2's behaviour) on a pull request: every test in one lane, no retry, and the
  test that depends on what ran before it failing there, as it should without a retry;
- this chapter's agent playbook: the preconditions, steps 2, 4 and 5, and Verify as written, against the same
  repository (steps 1 and 3 are what made that repository).

Not tested: a suite of hundreds of tests (the timings above are for 18); the `schedule` itself firing at night
(the run by hand takes the same path); and a pull request from a fork, which runs on GitHub's machines with the
same workflow (chapter 8, tier 3).
