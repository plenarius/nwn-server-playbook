#!/usr/bin/env bash
# guard-push.sh: refuse a push to a branch whose pull request is already merged or closed. Commits pushed there
# reach nobody: the pull request is done, and the work is quietly stranded. Chapter 15, tier 3.
#
# Two ways to install it, use either or both:
#   As git's pre-push hook, for any agent tool (and people):
#     install -D -m 755 guard-push.sh ~/.config/git/hooks/pre-push
#     git config --global core.hooksPath ~/.config/git/hooks
#   (core.hooksPath replaces each repository's own .git/hooks; see the chapter.)
#   As a Claude Code PreToolUse hook on Bash, which stops the command before it runs: claude-settings.json.
#
# It asks GitHub's API about the branch. GH_TOKEN, if set, is used for private repositories; a public one
# needs no token. If GitHub can't be asked (no network, rate limit), it lets the push through and says so.
set -u
api=${GITHUB_API:-https://api.github.com}

state_of() { # owner/repo branch -> "MERGED url", "CLOSED url", "OPEN url" or nothing
  # The token goes to curl as a config line on its standard input: never on a command line, and this keeps
  # git's own standard input (the refs) for the loop below.
  { if [ -n "${GH_TOKEN:-}" ]; then printf 'header = "Authorization: Bearer %s"\n' "$GH_TOKEN"; fi; } |
  curl -fsS --max-time 10 -K - -H 'Accept: application/vnd.github+json' \
    "$api/repos/$1/pulls?state=all&per_page=5&head=${1%%/*}:$2" 2>/dev/null | python3 -c '
import json, sys
prs = json.load(sys.stdin)
if prs:
    prs.sort(key=lambda p: p["state"] != "open")
    p = prs[0]
    print("OPEN" if p["state"] == "open" else "MERGED" if p.get("merged_at") else "CLOSED", p["html_url"])' 2>/dev/null
}

repo_of() { # a git URL -> owner/repo for github.com, nothing otherwise
  sed -nE 's#^(git@github\.com:|ssh://git@github\.com/|https?://([^/@]+@)?github\.com/)([^/]+/[^/]+)$#\3#p' <<<"$1" | sed 's#\.git$##'
}

check() { # repo branch; exit 2 if the branch's pull request is finished
  local st
  st=$(state_of "$1" "$2") || { echo "guard-push: could not ask GitHub about $2; letting the push through" >&2; return 0; }
  case $st in
    MERGED*|CLOSED*)
      echo "Blocked: the pull request for branch '$2' is ${st%% *} (${st#* }). Pushing would strand the commits." >&2
      echo "Fetch, make a new branch from the default branch, and open a new pull request." >&2
      exit 2 ;;
  esac
}

if [ $# -ge 2 ]; then
  # git pre-push: $1 remote name, $2 its URL; standard input: <local ref> <sha> <remote ref> <sha> per ref.
  # The repository is the one the remote fetches from, so a push URL elsewhere is still checked against it.
  repo=$(repo_of "$(git remote get-url "$1" 2>/dev/null || echo "$2")")
  [ -n "$repo" ] || exit 0
  while read -r _ lsha rref _; do
    [ "$lsha" = 0000000000000000000000000000000000000000 ] && continue   # a delete
    case $rref in refs/heads/*) check "$repo" "${rref#refs/heads/}" ;; esac
  done
  exit 0
fi

# Claude Code PreToolUse: JSON on standard input with the command and the folder it runs in.
input=$(cat)
{ IFS= read -r cmd; IFS= read -r cwd; } < <(python3 -c 'import json,sys; d=json.loads(sys.stdin.read() or "{}")
print(d.get("tool_input",{}).get("command","").replace("\n"," ")); print(d.get("cwd",""))' <<<"$input")
grep -qE '(^|[;&|[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push\b' <<<"$cmd" || exit 0
dir=$(sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^[:space:]]+)[[:space:]]+push.*/\1/p' <<<"$cmd")
dir=${dir:-$cwd}; dir=${dir/#\~/$HOME}
# An explicit branch after the remote (git push origin foo, HEAD:foo) wins over the checked-out branch.
ref=$(sed -nE 's/.*push([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^-[:space:]][^[:space:]]*[[:space:]]+([^-[:space:]][^[:space:];&|]*).*/\2/p' <<<"$cmd")
ref=${ref##*:}; ref=${ref#refs/heads/}
if [ -n "$ref" ] && [ "$ref" != HEAD ]; then branch=$ref
else branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0; [ "$branch" = HEAD ] && exit 0; fi
repo=$(repo_of "$(git -C "$dir" remote get-url origin 2>/dev/null)")
[ -n "$repo" ] || exit 0
check "$repo" "$branch"
exit 0
