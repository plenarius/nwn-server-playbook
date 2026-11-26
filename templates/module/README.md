# A module repository, to start from

Copy this folder to make the repository for your own module. Chapter 6 of the guide walks through it.

| File | What it is |
|---|---|
| `nasher.cfg` | Tells nasher where the module's files are and what to call the built module |
| `tools/setup.sh` | Run once per copy: makes nasher stop when a script fails to compile |
| `tools/check_compiled.py` | Looks inside a built module and lists scripts that should be compiled and are not |
| `.github/workflows/compile-check.yml` | Builds and checks the module on every pull request, on GitHub's machines |
| `.gitignore` | Keeps built files out of git |
| `example/mod_load.nss` | A small example script for the chapter's walk-through. Delete it when you are done |

Your module's own files go in `src/`, where `nasher unpack` puts them.
