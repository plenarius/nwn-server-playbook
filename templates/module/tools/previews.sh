#!/usr/bin/env bash
# previews.sh: pictures of the areas a pull request changes, before and after, drawn with nwn-bake, and the
# comment that shows them (chapter 8, tier 3). Run by .github/workflows/previews.yml; you can run it at home too.
#
#   tools/previews.sh draw BASE HEAD OUT     draw every changed area of HEAD and of BASE into OUT, write OUT/comment.md
#   tools/previews.sh publish PR OUT         put OUT's pictures on the branch "previews" and the comment on the PR
#   tools/previews.sh forget PR              take a closed pull request's pictures off the branch
#
# "draw" needs nwn-bake on PATH and your own installed copy of the game (NWN_ROOT, or NWN_GAME_DIR on your
# runners; haks: the user folder in NWN_BAKE_USER, if set); "publish" and "forget" need gh and a git remote
# they may push to.
#
# The pictures go on a branch of their own that holds nothing else, so they never touch your history, and are
# linked from one comment that each push to the pull request edits rather than adds to.
set -euo pipefail
LIMIT=${PREVIEW_LIMIT:-6}          # at most this many areas; more than that and it says so instead
BRANCH=${PREVIEW_BRANCH:-previews}
MARK='<!-- previews -->'
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
GAME=${NWN_GAME_DIR:-${NWN_ROOT:-}}

# Draws one area of a checkout. The module is the nasher project itself: nwn-bake reads src/ as it is.
draw_area() {
  local tree=$1 area=$2 out=$3
  [ -f "$tree/src/are/$area.are.json" ] || return 1
  mkdir -p "$out"
  nwn-bake area-iso "$tree" "$area" --view sw,top --format png --scale 8 --out "$out" --root "$GAME" \
    ${NWN_BAKE_USER:+--user "$NWN_BAKE_USER"} --name '{area}.{view}.{ext}' --layout flat > /dev/null 2> "$out/$area.log"
}

draw() {
  local base=$1 head=$2 out=$3 areas n=0 before
  # Only drawing needs the game: "forget" runs on GitHub's machines, which have none.
  [ -n "$GAME" ] || { echo "no game: set NWN_ROOT to your installed copy of NWN:EE" >&2; exit 1; }
  rm -rf "$out"; mkdir -p "$out/before" "$out/after"
  base=$(git merge-base "$base" "$head")
  # An area is three files (.are, .git, .gic); any of them changing changes how it looks, or what is in it.
  mapfile -t areas < <(git diff --name-only "$base" "$head" -- 'src/are/*' 'src/git/*' 'src/gic/*' |
    sed -E 's|.*/([^/.]+)\..*|\1|' | sort -u)
  {
    echo "$MARK"
    echo "### Pictures of the changed areas"
    echo
    if [ ${#areas[@]} -eq 0 ]; then
      echo "This pull request changes no area."
    elif [ ${#areas[@]} -gt "$LIMIT" ]; then
      echo "This pull request changes ${#areas[@]} areas, more than the $LIMIT I draw. Look at them in the toolset."
    fi
  } > "$out/comment.md"
  [ ${#areas[@]} -gt 0 ] && [ ${#areas[@]} -le "$LIMIT" ] || return 0
  before=$(mktemp -d); trap 'git worktree remove --force "$before" 2>/dev/null || true' RETURN
  git worktree add -q --detach "$before" "$base"
  echo "| Area | Before | After |" >> "$out/comment.md"
  echo "|---|---|---|" >> "$out/comment.md"
  for a in "${areas[@]}"; do
    local was=missing now=missing
    if draw_area "$before" "$a" "$out/before"; then was=drawn; elif [ -f "$before/src/are/$a.are.json" ]; then was=failed; fi
    if draw_area "$ROOT" "$a" "$out/after"; then now=drawn; elif [ -f "src/are/$a.are.json" ]; then now=failed; fi
    echo "$a: before $was, after $now"
    cell() { case $1 in drawn) echo "![$a $3](IMG/$2/$a.$3.png)" ;; missing) echo "(none)" ;; *) echo "(could not draw: see the run's log)" ;; esac; }
    for v in sw top; do
      echo "| \`$a\` $v | $(cell $was before $v) | $(cell $now after $v) |" >> "$out/comment.md"
    done
    n=$((n + 1))
  done
  echo >> "$out/comment.md"
  echo "Drawn with nwn-bake from the area files alone (no game client). Before is the branch this pull request started from." >> "$out/comment.md"
}

publish() {
  local pr=$1 out=$2 repo sha dir tree commit parent body id url
  repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
  # A pull request's checkout is GitHub's trial merge; name the pictures after the pull request's own commit.
  sha=$(git rev-parse --short "${PREVIEW_SHA:-HEAD}")
  dir="pr-$pr/$sha"
  url="https://github.com/$repo/blob/$BRANCH/$dir"
  # One commit on the pictures branch, made with git's own plumbing, so the working tree is never touched.
  local idx; idx=$(mktemp); rm -f "$idx"
  export GIT_INDEX_FILE=$idx
  git fetch -q origin "$BRANCH" 2>/dev/null && parent=$(git rev-parse FETCH_HEAD) || parent=
  [ -z "$parent" ] || git read-tree "$parent"
  for f in "$out"/before/*.png "$out"/after/*.png; do
    [ -f "$f" ] || continue
    git update-index --add --cacheinfo "100644,$(git hash-object -w "$f"),$dir/$(basename "$(dirname "$f")")/$(basename "$f")"
  done
  tree=$(git write-tree)
  commit=$(git -c user.name=previews -c user.email=previews@localhost commit-tree "$tree" ${parent:+-p "$parent"} -m "Pictures for #$pr at $sha")
  unset GIT_INDEX_FILE; rm -f "$idx"
  git push -q origin "$commit:refs/heads/$BRANCH"
  body=$(sed "s|IMG/\([a-z]*\)/\([^)]*\)|$url/\1/\2?raw=true|g" "$out/comment.md")
  id=$(gh api "repos/$repo/issues/$pr/comments" --paginate -q ".[] | select(.body | startswith(\"$MARK\")) | .id" | head -n 1)
  if [ -n "$id" ]; then
    gh api -X PATCH "repos/$repo/issues/comments/$id" -f body="$body" > /dev/null && echo "comment $id updated"
  else
    gh api "repos/$repo/issues/$pr/comments" -f body="$body" -q .html_url
  fi
}

forget() {
  local pr=$1 parent tree commit idx
  git fetch -q origin "$BRANCH" 2>/dev/null || return 0
  parent=$(git rev-parse FETCH_HEAD)
  git ls-tree --name-only "$parent" | grep -qx "pr-$pr" || { echo "no pictures for #$pr"; return 0; }
  idx=$(mktemp); rm -f "$idx"
  GIT_INDEX_FILE=$idx git read-tree "$parent"
  GIT_INDEX_FILE=$idx git rm -rq --cached "pr-$pr"
  tree=$(GIT_INDEX_FILE=$idx git write-tree); rm -f "$idx"
  commit=$(git -c user.name=previews -c user.email=previews@localhost commit-tree "$tree" -p "$parent" -m "#$pr closed")
  git push -q origin "$commit:refs/heads/$BRANCH" && echo "pictures for #$pr removed"
}

case ${1:-} in
  draw) draw "${2:?base}" "${3:?head}" "${4:?out}" ;;
  publish) publish "${2:?pull request number}" "${3:?out}" ;;
  forget) forget "${2:?pull request number}" ;;
  *) sed -n '2,8p' "$0" >&2; exit 2 ;;
esac
