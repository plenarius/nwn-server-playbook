#!/usr/bin/env bash
# borg-wind-back.sh: undo what happened to an append-only borg repository after a given moment.
# Chapter 12, tier 2. Run it on the storage machine, as the account that owns the repositories.
#
#   borg-wind-back.sh REPO_DIR             list the repository's transactions, oldest first, with their times
#   borg-wind-back.sh REPO_DIR N --apply   keep transaction N and everything before it; undo everything after
#
# In append-only mode borg never changes or removes what it has written. A delete or prune only adds a note
# that says "this is gone", in a new transaction. Removing those later transactions brings the archives back.
# Before it touches anything, --apply makes a hard-linked copy beside the repository (REPO_DIR.before-N),
# which costs almost no space, so a wrong N can be put right.
#
# This only works until someone with a key that may delete runs "borg compact" on the repository; borg-prune.sh
# stops before that when it sees an archive missing. Afterwards, every client that saw the later state needs
# "borg delete --cache-only" and its security note removed: chapter 12 shows the two commands.
set -euo pipefail
DIR=$(cd "${1:?usage: borg-wind-back.sh REPO_DIR [N --apply]}" && pwd)
N=${2:-}
cd "$DIR"
[ -f "$DIR/transactions" ] && [ -d "$DIR/data" ] || { echo "$DIR is not a borg repository" >&2; exit 2; }

# The log keeps lines of transactions that were wound back before, and their numbers come round again; a
# transaction is current when its segment file is still there, and its newest line is the one that counts.
current() {
  tac "$DIR/transactions" | awk '!seen[$2]++' | tac | while read -r line; do
    t=$(printf '%s' "$line" | sed -n 's/^transaction \([0-9]*\),.*/\1/p')
    [ -n "$(find "$DIR/data" -type f -name "$t")" ] && echo "$line"
  done
}

if [ -z "$N" ]; then
  current
  echo "Pick the last transaction from before the trouble, then run: $0 $DIR N --apply"
  exit 0
fi
[ "${3:-}" = --apply ] || { echo "add --apply to wind back to transaction $N" >&2; exit 2; }
current | grep "^transaction $N," > /dev/null || { echo "there is no transaction $N" >&2; exit 2; }
last=$(ls "$DIR" | sed -n 's/^index\.\([0-9]*\)$/\1/p' | sort -n | tail -1)
[ -n "$last" ] && [ "$last" -gt "$N" ] || { echo "transaction $N is already the newest" >&2; exit 2; }

cp -al "$DIR" "$DIR.before-$N"
echo "copy kept: $DIR.before-$N"
rm -f "$DIR"/hints.* "$DIR"/index.* "$DIR"/integrity.*
removed=0
while read -r f; do
  rm -f "$f"; removed=$((removed + 1))
done < <(find "$DIR/data" -type f -regex '.*/[0-9]+' | awk -F/ -v n="$N" '$NF + 0 > n + 0')
echo "removed $removed segment files after transaction $N; borg rebuilds its index on the next use"
