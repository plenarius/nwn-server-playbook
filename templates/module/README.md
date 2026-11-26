# A module repository, to start from

Copy this folder to make the repository for your own module. Chapter 6 of the guide walks through it.

| File | What it is |
|---|---|
| `nasher.cfg` | Tells nasher where the module's files are and what to call the built module |
| `tools/setup.sh` | Run once per copy: makes nasher stop when a script fails to compile |
| `tools/check_compiled.py` | Looks inside a built module and lists scripts that should be compiled and are not |
| `.github/workflows/compile-check.yml` | Builds and checks the module on every pull request, on GitHub's machines |
| `tests/run.sh` | Builds the module with its tests and runs them on a headless NWNX server (chapter 6, tier 2) |
| `tests/nss/` | The test runner (`t_boot`, `t_runner`, `inc_test`) and four example tests, `t_<system>_<case>` |
| `tests/compose.yaml` | The test server: your NWNX image and an empty database, on a network with no route out |
| `tests/tools/results.py` | Reads the test server's logs, prints the results, writes `junit.xml` |
| `tests/tools/fetch_content.sh` | Downloads your haks and talk table from your download address, for the test server |
| `tests/tools/check_content.py` | Before a run, names any hak or talk table the module lists and the test server lacks |
| `tests/tools/plan.py` | Says which tests a change can reach, and deals them into lanes (chapter 6, tier 3) |
| `tests/quarantine.txt` | Tests whose failure is reported but doesn't fail the run, each with an issue number (tier 3) |
| `tests/tools/flake_report.py` | Turns the records of flaky and quarantined tests into one report (tier 3) |
| `.github/workflows/tests.yml` | Runs the tests on every pull request and every night; in tier 3 only the selected ones, in lanes, with one retry |
| `.github/workflows/flake-report.yml` | Every morning, the flake report on the run's page (chapter 6, tier 3) |
| `.github/workflows/previews.yml` | Pictures of the areas a pull request changes, on your own runners (chapter 8, tier 3) |
| `tools/previews.sh` | Draws those pictures with nwn-bake and posts them (chapter 8, tier 3) |
| `.github/workflows/release.yml` | On a `v*` tag: tests, builds, makes a GitHub release, puts the module on staging |
| `.github/actions/nwn-tools/` | The tool install the two workflows share |
| `.gitignore` | Keeps built files out of git |
| `migrations/` | Numbered SQL files that change the database's tables, run once each by the game host's `migrate.sh` (chapter 5, tier 2) |
| `database/` | Two migrations (a work queue, revision counters) and three scripts that poll them, for chapter 5, tier 3. Copy the migrations into `migrations/` under the next numbers and the scripts into `src/nss/` |
| `example/mod_load.nss` | A small example script for the chapter's walk-through. Delete it when you are done |

Your module's own files go in `src/`, where `nasher unpack` puts them.
