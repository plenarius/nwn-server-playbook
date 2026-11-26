#!/usr/bin/env bash
# The release train's freeze, from your own computer. Chapter 16, tier 3.
#
#   tools/freeze.sh start HOURS   freeze main for HOURS: only pull requests labelled release-fix may merge
#   tools/freeze.sh end           lift the freeze now
#   tools/freeze.sh status        is main frozen, and which open pull requests wait
#   tools/freeze.sh notes TAG     the release notes TAG would get now, from merged pull requests' labels,
#                                 since the last release that isn't a candidate (-rc); changes nothing
#
# Needs gh, logged in as someone who may change the repository's variables (Admin, or Maintain with variables).
# REPO=owner/name to choose the repository; by default the one this folder's git remote points at.
# start and end re-run the "Release train" check on every open pull request, so each one shows the freeze at
# once: a check only runs by itself when its pull request changes.
set -euo pipefail

REPO=${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}
WORKFLOW="Release train"

rerun_open() {
  local n=0 pr sha runs run
  while read -r pr sha; do
    # Every run on the commit, not only the newest: each pull request event makes its own run, and GitHub counts
    # a check as passed if any run of it passed. One old green run would let a pull request through a freeze.
    runs=$(gh run list -R "$REPO" -w "$WORKFLOW" -c "$sha" -L 50 --json databaseId -q '.[].databaseId')
    [ -n "$runs" ] || { echo "#$pr: no check yet; it runs at the pull request's next change" >&2; continue; }
    for run in $runs; do
      # A run still going can't be re-run; it reads the variable fresh as it starts anyway.
      gh run rerun "$run" -R "$REPO" > /dev/null 2>&1 || echo "#$pr: run $run is still going; it will see the change" >&2
    done
    n=$((n + 1))
  done < <(gh pr list -R "$REPO" -B main -s open -L 200 --json number,headRefOid -q '.[] | "\(.number) \(.headRefOid)"')
  echo "re-ran the checks on $n open pull request$([ "$n" = 1 ] || echo s)"
}

case "${1:-}" in
  start)
    [[ "${2:-}" =~ ^[0-9]+$ ]] || { echo "usage: $0 start HOURS" >&2; exit 2; }
    until=$(date -u -d "+$2 hours" +%Y-%m-%dT%H:%MZ)
    gh variable set FREEZE_UNTIL -R "$REPO" -b "$until"
    echo "main is frozen until $until UTC: only release-fix pull requests may merge"
    rerun_open
    ;;
  end)
    gh variable delete FREEZE_UNTIL -R "$REPO" 2> /dev/null || true
    echo "the freeze is lifted"
    rerun_open
    ;;
  status)
    until=$(gh variable get FREEZE_UNTIL -R "$REPO" 2> /dev/null || true)
    if [ -n "$until" ] && [ "$(date -u -d "$until" +%s)" -gt "$(date -u +%s)" ]; then
      echo "frozen until $until UTC"
    else
      echo "not frozen${until:+ (FREEZE_UNTIL $until has passed: run '$0 end' to tidy it and re-run the checks)}"
    fi
    gh pr list -R "$REPO" -B main -s open --json number,title,labels \
      -q '.[] | "#\(.number) \(.title)  [\([.labels[].name] | join(", "))]"'
    ;;
  notes)
    [ -n "${2:-}" ] || { echo "usage: $0 notes TAG" >&2; exit 2; }
    prev=$(gh release list -R "$REPO" -L 100 --json tagName,isPrerelease,isDraft \
      -q '[.[] | select(.isPrerelease | not) | select(.isDraft | not) | .tagName | select(test("-rc") | not)][0] // empty')
    args=(-f tag_name="$2" -f target_commitish=main)
    [ -n "$prev" ] && args+=(-f previous_tag_name="$prev")
    gh api -X POST "repos/$REPO/releases/generate-notes" "${args[@]}" -q .body
    ;;
  *)
    sed -n '2,14p' "$0" >&2
    exit 2
    ;;
esac
