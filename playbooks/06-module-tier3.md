# Playbook 6, tier 3. Choosing tests, lanes, and flaky tests kept honest

For an agent. The chapter for people is [`chapters/06-module.md`](../chapters/06-module.md), section "Tier 3".
Follow the steps in order. Do not go on from a step whose check fails.

`GUIDE` is the root of this repository on the person's computer. Run every command in `REPO_DIR` unless it says
otherwise.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `GUIDE` | Where this repository is | none: a person gives it |
| `REPO_DIR` | The module's repository from playbook 6 | `~/mymodule` |
| `GH_REPO` | Its GitHub repository, `owner/name` | none: a person gives it |
| `LANES` | At most this many lanes | `3` |

Secrets: none. GitHub access is the person's own `gh` login.

## Preconditions

Playbook 6, tier 2 is done, and the tests pass at home and on GitHub:

```sh
ls tests/run.sh .github/workflows/tests.yml | wc -l; git status -s | wc -l
gh run list -R $GH_REPO -w Tests -b main -L 1 --json conclusion -q '.[0].conclusion'
tests/run.sh > /tmp/t3-pre.txt; echo "exit $?"; tail -1 /tmp/t3-pre.txt
```

Success: `2`, `0` (a clean checkout), `success`, `exit 0` and `N passed, 0 failed, ...`. A failing test now: stop and
ask; this playbook is not the place to fix it.

## Steps

### 1. Bring the new files in

```sh
git checkout -q -b tests-tier3 && T="$GUIDE/templates/module"
cp "$T/tests/run.sh" tests/ && cp "$T/tests/nss/t_runner.nss" tests/nss/ && cp "$T"/tests/tools/{plan.py,results.py,flake_report.py} tests/tools/
[ -f tests/quarantine.txt ] || cp "$T/tests/quarantine.txt" tests/
cp .github/workflows/tests.yml /tmp/tests-tier2.yml && cp "$T"/.github/workflows/{tests.yml,flake-report.yml} .github/workflows/
grep -E '^  (NWNX_IMAGE|NWSYNC_URL|NASHER_VERSION|NEVERWINTER_VERSION):' /tmp/tests-tier2.yml .github/workflows/tests.yml
```

Success: the four settings listed twice. Where the old file (`/tmp/tests-tier2.yml`) has a different value, set
the new file's line to the old value (`sed -i 's|^  NWSYNC_URL: .*|  NWSYNC_URL: "..."|' .github/workflows/tests.yml`),
then list them again: each pair the same.

```sh
tests/run.sh > /tmp/t3-all.txt; echo "exit $?"; tail -1 /tmp/t3-all.txt
first=$(sed -n 's/^PASS  //p' /tmp/t3-all.txt | head -1); tests/run.sh --no-build --filter "$first,t_nothing_" | tail -2
```

Success: the same result as the preconditions; then one test run by its whole name, `PASS  <name>` and
`1 passed, 0 failed, 0 skipped`.

### 2. Read what the planner says

```sh
python3 tests/tools/plan.py --lanes $LANES
python3 tests/tools/plan.py --base origin/main --lanes $LANES
git log --oneline -5 origin/main | while read sha _; do echo "== $sha"; python3 tests/tools/plan.py --base $sha~1 --head $sha --lanes $LANES | head -2; done
```

Success: `full: no base to compare with: every test` and up to `LANES` lane lines with every test once; then a mode
line for the current branch (`full`, since step 1 changed the harness); then a mode line for each of the last five
merged commits. Report those five to the person, as "this change would have run these tests". If a commit that
changed a script shows `boot` or `none`, say so plainly: those are changes the planner thinks no test reaches.

### 3. Switch it on

**Ask first.** Tell the person which settings change (`TEST_SELECT` true, `TEST_LANES` to `LANES`, `TEST_RETRY` true)
and that every later pull request runs only its selected tests, and wait for a yes. They may want one at a time.

```sh
sed -i 's/^  TEST_SELECT: .*/  TEST_SELECT: "true"/; s/^  TEST_LANES: .*/  TEST_LANES: "'$LANES'"/; s/^  TEST_RETRY: .*/  TEST_RETRY: "true"/' .github/workflows/tests.yml
grep -E '^  TEST_(SELECT|LANES|LANE_LEAST|RETRY):' .github/workflows/tests.yml
git add -A && git commit -q -m "Tests: selection, lanes, one retry, a flake report" && git push -q -u origin tests-tier3 && gh pr create -R $GH_REPO --fill | tail -1
sleep 20; RUN=$(gh run list -R $GH_REPO -w Tests -b tests-tier3 -L 1 --json databaseId -q '.[0].databaseId'); gh run watch $RUN -R $GH_REPO --exit-status > /dev/null; echo "exit $?"
gh run view $RUN -R $GH_REPO --json jobs -q '.jobs[] | "\(.name) \(.conclusion)"'
```

Success: the four settings as asked; a pull request URL; `exit 0`; `plan success`, one `lane N success` per lane
(this pull request changes the harness, so every test runs), `tests success`. A person merges it.

### 4. A flaky test, at home

Shows the person what the retry and the quarantine do, with a throwaway test that fails one time in two.

```sh
printf '#include "inc_test"\nvoid main()\n{\n    AssertInt(Random(2), 0, "heads");\n}\n' > tests/nss/t_zz_coin.nss
tests/run.sh --filter t_zz_ > /dev/null; for i in 1 2 3 4; do tests/run.sh --no-build --retry --filter t_zz_ | grep -E '^(PASS|FAIL|FLAKY)'; done
echo "t_zz_coin   # issue 0, $(date +%F): playbook check" >> tests/quarantine.txt
for i in 1 2 3; do tests/run.sh --no-build --filter t_zz_ | grep -E '^(PASS|QUARANTINED)'; echo "exit ${PIPESTATUS[0]}"; done
rm tests/nss/t_zz_coin.nss && git checkout -q tests/quarantine.txt && git status -s | wc -l
```

Success: four lines, each `PASS`, `FLAKY` or `FAIL  t_zz_coin` (two failures in a row); then three `PASS` or
`QUARANTINED` lines, each with `exit 0`; then `0`. Show the person one `FLAKY` line and one `QUARANTINED` line if
there were any.

### 5. The flake report

```sh
gh workflow run "Flake report" -R $GH_REPO; sleep 20; RUN=$(gh run list -R $GH_REPO -w "Flake report" -L 1 --json databaseId -q '.[0].databaseId'); gh run watch $RUN -R $GH_REPO --exit-status > /dev/null; echo "exit $?"
gh run view $RUN -R $GH_REPO --log | grep -E 'runs with records|Flake report|^.*\| `t_' | cut -f3 | head
```

Success: `exit 0`, `N runs with records`, `## Flake report: the last 14 days` and either `No test was flaky...` or a
table row per test. Report the rows to the person.

## Verify

```sh
gh run list -R $GH_REPO -w Tests -b main -L 1 --json conclusion,databaseId -q '.[0] | "\(.conclusion) \(.databaseId)"'
RUN=$(gh run list -R $GH_REPO -w Tests -b main -L 1 --json databaseId -q '.[0].databaseId'); gh api "repos/$GH_REPO/actions/runs/$RUN/artifacts" -q '.artifacts[] | "\(.name) \(.size_in_bytes)"'
grep -vE '^\s*(#|$)' tests/quarantine.txt | grep -vcE '#.*(issue|#) *[0-9]+'
```

Success: `success` on `main` after the merge; one `test-logs-lane-N` artifact per lane, each bigger than 1000 bytes
(a size near 0 means the logs were not kept: check `include-hidden-files: true`); `0` (every quarantined test has an
issue number).

## Roll back

Set `TEST_SELECT` to `"false"`, `TEST_LANES` to `"1"` and `TEST_RETRY` to `"false"` in `tests.yml` in a pull
request: the workflow then runs every test in one lane, as in tier 2. The new `run.sh`, `results.py` and runner
behave as before without `--retry` and with a single filter. Delete `flake-report.yml` to stop the report.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- step 3, and any later change to `TEST_SELECT`, `TEST_LANES`, `TEST_LANE_LEAST` or `TEST_RETRY`;
- adding a test to `tests/quarantine.txt`, or taking one off: that is a person's call, with an issue number;
- changing, skipping or deleting a test to make a run green;
- a test the planner should reach and doesn't (a `boot` or `none` for a change to a script a test uses): report
  the change and the test;
- changing the ruleset's required checks.
