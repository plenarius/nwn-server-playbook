#!/usr/bin/env bash
# Runs before every job on a self-hosted runner (ACTIONS_RUNNER_HOOK_JOB_STARTED). Exits 1, and so fails the job
# before its first step, when the job is from someone else's copy of the repository (a fork) or from a repository
# this runner isn't for. This is the lock on the runner itself: a pull request from a fork can change the
# workflow it runs, so the "fork goes to GitHub's machines" rule in the workflow is a courtesy, and this is the
# rule (chapter 8, tier 3).
set -euo pipefail
event=${GITHUB_EVENT_PATH:?}
repo=${GITHUB_REPOSITORY:?}

# RUNNER_REPOS: the repositories this runner may work for, separated by spaces (set by runners.sh).
case " ${RUNNER_REPOS:-$repo} " in
  *" $repo "*) ;;
  *) echo "refused: this runner is not for $repo" >&2; exit 1 ;;
esac

case ${GITHUB_EVENT_NAME:-} in
  pull_request|pull_request_target|pull_request_review|pull_request_review_comment)
    head=$(jq -r '.pull_request.head.repo.full_name // empty' "$event")
    if [ "$head" != "$repo" ]; then
      echo "refused: a pull request from ${head:-a deleted repository}, not from $repo itself; self-hosted runners never run code from forks" >&2
      exit 1
    fi ;;
  issue_comment)
    # A comment on a pull request can start a job too; the comment's author may be anyone.
    echo "refused: jobs started by comments don't run on self-hosted runners" >&2
    exit 1 ;;
esac
echo "job from $repo ($GITHUB_EVENT_NAME) accepted on $(hostname)"
