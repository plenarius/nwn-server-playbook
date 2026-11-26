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
| `.github/workflows/tests.yml` | Runs the tests on every pull request, on GitHub's machines |
| `.github/workflows/release.yml` | On a `v*` tag: tests, builds, makes a GitHub release, puts the module on staging |
| `.github/actions/nwn-tools/` | The tool install the two workflows share |
| `.gitignore` | Keeps built files out of git |
| `migrations/` | Numbered SQL files that change the database's tables, run once each by the game host's `migrate.sh` (chapter 5, tier 2) |
| `example/mod_load.nss` | A small example script for the chapter's walk-through. Delete it when you are done |

Your module's own files go in `src/`, where `nasher unpack` puts them.
