# Playbook 8, tier 2. GitHub's machines, with Docker

For an agent. The chapter for people is [`chapters/08-ci.md`](../chapters/08-ci.md), section "Tier 2". It checks
what playbook 6's tier 2 set up; it creates nothing except one throwaway branch and run in step 4, which it
deletes. Follow the steps in order. Do not go on from a step whose check fails.

Tier 1 has no playbook of its own: chapter 6's compile check (playbook 6, steps 7 and 8) is tier 1's CI.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `REPO_DIR` | The module's repository | `~/mymodule` |
| `GH_REPO` | Its GitHub repository, `owner/name` | none: a person gives it |
| `TEST` | One test to check for flakiness, in step 5 | none: a person gives it, or skip step 5 |

Secrets: none pass through you. You read secret names, never values.

## Preconditions

Playbook 6, tier 2 is done:

```sh
cd "$REPO_DIR" && ls .github/workflows/tests.yml .github/workflows/release.yml .github/actions/nwn-tools/action.yml | wc -l
gh run list -R $GH_REPO -w Tests -b main -L 1 --json conclusion -q '.[0].conclusion'
gh api repos/$GH_REPO/environments/staging -q .name
```

Success: `3`, `success`, `staging`.

## Steps

### 1. The machine, and the safety settings

```sh
grep -c 'timeout-minutes' .github/workflows/tests.yml .github/workflows/release.yml
grep -c 'cancel-in-progress: true' .github/workflows/tests.yml
grep -B1 'run.sh' .github/workflows/tests.yml | grep -c 'pipefail'
```

Success: `tests.yml:1`, `release.yml:2`, then `1`, then `1`. A `0` for `pipefail` means a failed test can pass the
run: stop and ask.

### 2. Nothing cached that doesn't pay

```sh
grep -c 'actions/cache' .github/workflows/*.yml .github/actions/nwn-tools/action.yml
RUN=$(gh run list -R $GH_REPO -w Tests -b main -L 1 --json databaseId -q '.[0].databaseId'); gh run view $RUN -R $GH_REPO --json jobs -q '.jobs[0].steps[] | "\(.name) \(.startedAt) \(.completedAt)"'
```

Success: `0` for every file; the step times, with the tool step and `Run the tests` taking nearly all of the job
(on the test, 27 s and 23 s of 52). If a person asks for a
cache, measure both ways first (the chapter's step 3) and report the numbers; do not add one that is not faster.

### 3. The environment's rules

```sh
gh api repos/$GH_REPO/environments/staging -q '.deployment_branch_policy'
gh api repos/$GH_REPO/environments/staging/deployment-branch-policies -q '.branch_policies[] | "\(.type) \(.name)"'
gh secret list -R $GH_REPO --env staging --json name -q '.[].name'; gh secret list -R $GH_REPO --json name -q '.[].name' | grep -c STAGING
gh variable list -R $GH_REPO --env staging --json name -q '.[].name' | sort | tr '\n' ' '
```

Success: `{"custom_branch_policies":true,"protected_branches":false}`; `tag v*` and nothing else;
`STAGING_SSH_KEY`, then `0` (the key is not also a repository secret); `STAGING_HOST STAGING_KNOWN_HOSTS`. Anything
else: stop and ask, and change nothing.

### 4. Prove a branch can't reach the key

**Ask first**: this pushes a branch with a throwaway workflow and deletes it again.

```sh
git checkout -q -b env-probe origin/main && mkdir -p .github/workflows && printf 'name: Env probe\non:\n  push:\n    branches: [env-probe]\njobs:\n  probe:\n    runs-on: ubuntu-latest\n    environment: staging\n    steps:\n      - run: echo "this should never run"\n' > .github/workflows/env-probe.yml && git add .github/workflows/env-probe.yml && git commit -q -m "Env probe (throwaway)" && git push -q -u origin env-probe
sleep 30; RUN=$(gh run list -R $GH_REPO -w "Env probe" -L 1 --json databaseId -q '.[0].databaseId'); gh run view $RUN -R $GH_REPO 2>&1 | grep -o 'not allowed to deploy to staging[^.]*'
git checkout -q main && git push -q origin --delete env-probe && git branch -q -D env-probe
```

Success: `not allowed to deploy to staging due to environment protection rules`. If the probe job ran instead,
stop and ask: the key is reachable from any branch.

### 5. A flaky test, at home

Only when a person names a test that failed once and passed on a rerun.

```sh
tests/run.sh --filter $TEST > /dev/null; for i in $(seq 20); do tests/run.sh --no-build --filter $TEST > /dev/null || { echo "failed on run $i"; break; }; done; echo "done"
```

Success: either `failed on run N`, with that run's logs in `tests/.run/logs/` (report the failed assert and any
script error from them), or only `done` (it didn't fail in 20 runs: say so, and that this doesn't prove it fixed).

## Verify

```sh
gh run list -R $GH_REPO -L 5 --json workflowName,conclusion,headBranch -q '.[] | "\(.workflowName) \(.headBranch) \(.conclusion)"'
git ls-remote --heads origin env-probe | wc -l
```

Success: no run you started is still in progress; `0` (the probe branch is gone).

## Roll back

Only step 4 makes anything: delete the `env-probe` branch if it is still there. Its run stays in the Actions list;
a person can delete it there.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- step 4;
- changing an environment's rules, a secret or a variable;
- adding a retry to a workflow, or skipping or deleting a test to make a run green;
- moving a job to a self-hosted runner.
