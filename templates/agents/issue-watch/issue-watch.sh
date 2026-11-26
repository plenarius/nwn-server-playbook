#!/usr/bin/env bash
# issue-watch.sh: start one agent per new issue, one at a time, to triage it into a draft. Run every few
# minutes by issue-watch.timer, as the agent user on a worker. Chapter 15, tier 3.
#
# Settings: ~/.config/issue-watch/issue-watch.conf (ISSUE_WATCH_CONF= for another; see
# issue-watch.conf.example): the repositories to watch and the command that starts an agent.
# For each watched repository, on its first run it only notes the newest issue number (the baseline), so old
# issues are left alone. After that, each open issue above the baseline is marked done before its agent
# starts (a crash never starts it twice), its prompt gets {{N}} and {{REPO}} filled in, and the agent runs
# until it finishes; the next issue waits. To run an issue again, delete its done/<n> file.
# It uses no agent time until an issue arrives. The agent, not this script, labels, comments and drafts.
set -uo pipefail
CONF=${ISSUE_WATCH_CONF:-$HOME/.config/issue-watch/issue-watch.conf}
. "$CONF"
[ -r "${SECRETS:-/run/agent/secrets.env}" ] && { set -a; . "${SECRETS:-/run/agent/secrets.env}"; set +a; }
API=${GITHUB_API:-https://api.github.com}
STATE=${STATE:-$HOME/.local/state/issue-watch}
mkdir -p "$STATE"
exec 9>"$STATE/lock"; flock -n 9 || exit 0   # one watcher at a time; the next run picks up what's left

gh_get() { # path -> JSON; the token as a curl config line on standard input, never on the command line
  { if [ -n "${GH_TOKEN:-}" ]; then printf 'header = "Authorization: Bearer %s"\n' "$GH_TOKEN"; fi; } |
    curl -fsS --max-time 30 -K - -H 'Accept: application/vnd.github+json' "$API$1"
}

for row in "${WATCH[@]}"; do
  read -r REPO DIR BASE PROMPT <<<"$row"
  D="$STATE/${REPO//\//_}"; mkdir -p "$D/done"
  if [ ! -s "$D/baseline" ]; then
    j=$(gh_get "/repos/$REPO/issues?state=all&per_page=1") || { echo "$REPO: GitHub refused or didn't answer" >&2; continue; }
    n=$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d[0]["number"] if d else 0)' <<<"$j")
    echo "$n" > "$D/baseline"
    echo "$REPO: baseline #$n; only issues after it will be triaged"
    continue
  fi
  BASELINE=$(cat "$D/baseline")
  # Open issues (not pull requests) above the baseline, oldest first: "number<TAB>title".
  j=$(gh_get "/repos/$REPO/issues?state=open&per_page=100&sort=created&direction=asc") || { echo "$REPO: could not list issues" >&2; continue; }
  list=$(python3 -c '
import json, sys
for i in json.load(sys.stdin):
    if "pull_request" not in i and i["number"] > int(sys.argv[1]):
        print(i["number"], i["title"].replace("\t", " ")[:80], sep="\t")' "$BASELINE" <<<"$j")
  while IFS=$'\t' read -r N TITLE; do
    [ -n "$N" ] || continue
    [ -e "$D/done/$N" ] && continue
    date -Is > "$D/done/$N"
    echo "$REPO#$N: starting triage ($TITLE)"
    git -C "$DIR" fetch -q origin "$BASE" || echo "$REPO#$N: fetch failed; the agent starts from the last fetch" >&2
    export REPO N TITLE DIR BASE BRANCH="fix/issue-$N"
    sed -e "s/{{N}}/$N/g" -e "s#{{REPO}}#$REPO#g" -e "s#{{BASE}}#$BASE#g" "$(dirname "$CONF")/$PROMPT" |
      bash -c "$AGENT_CMD" > "$D/done/$N.log" 2>&1
    echo "$REPO#$N: agent finished, exit $? (log $D/done/$N.log)"
  done <<<"$list"
done
