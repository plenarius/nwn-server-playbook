#!/usr/bin/env bash
# Puts a pull request's module build, or main's, on the dev server (chapter 14). Run it on your own computer.
#
#   load-build.sh pr 12      the module the compile check built for pull request 12's newest commit
#   load-build.sh main       the module the compile check built for the newest commit on main
#   load-build.sh rollback   the build that was on the dev server before
#   load-build.sh status     what is on the dev server now
#
# Settings, from the environment:
#   GH_REPO   the module's repository, owner/name
#   CONTROL   the control host, as the deploy user: nwn@203.0.113.20
#   DEV_KEY   your key for the dev server, the one bound to dev.sh (default ~/.ssh/mymodule-dev)
#
# It builds nothing itself: it fetches the very file chapter 6's compile check built and checked, so what the dev
# server runs is what passed the check. GitHub keeps those files for 14 days; for an older commit, run the check
# again from the pull request's page (Re-run jobs).
set -euo pipefail
: "${GH_REPO:?set GH_REPO to owner/name}" "${CONTROL:?set CONTROL to nwn@your-control-host}"
DEV_KEY=${DEV_KEY:-$HOME/.ssh/mymodule-dev}
dev() { ssh -i "$DEV_KEY" -o IdentitiesOnly=yes "$CONTROL" "$@"; }

case ${1:-} in
  pr) [[ ${2:-} =~ ^[0-9]+$ ]] || { echo "usage: load-build.sh pr NUMBER" >&2; exit 2; }
      sha=$(gh pr view "$2" -R "$GH_REPO" --json headRefOid -q .headRefOid)
      label=pr-$2-${sha:0:7} ;;
  main) sha=$(gh api "repos/$GH_REPO/commits/main" -q .sha)
      label=main-${sha:0:7} ;;
  rollback | status) dev "$1"; exit ;;
  *) echo "usage: load-build.sh pr NUMBER | main | rollback | status" >&2; exit 2 ;;
esac

run=$(gh run list -R "$GH_REPO" -w "Compile check" -c "$sha" -s success -L 1 --json databaseId -q '.[0].databaseId')
[ -n "$run" ] || { echo "no passing compile check for ${sha:0:7} yet; wait for it, or look at the pull request's checks" >&2; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
gh run download "$run" -R "$GH_REPO" -n module -D "$tmp"
mods=("$tmp"/*.mod)
[ "${#mods[@]}" = 1 ] && [ -f "${mods[0]}" ] || { echo "the check's artifact should hold one .mod file" >&2; exit 1; }
echo "compile check run $run built $(basename "${mods[0]}") for ${sha:0:7}"
dev "load $label" < "${mods[0]}"
