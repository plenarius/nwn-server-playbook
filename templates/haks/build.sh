#!/usr/bin/env bash
# Builds your custom content from the files in this repository.
#   every folder in haks/         becomes  build/hak/<folder>.hak
#   every tlk/<name>.tlk.json     becomes  build/tlk/<name>.tlk
# Needs nwn_erf and nwn_tlk (the neverwinter.nim tools) on your PATH.
#
# MODELS=compile (chapter 7, tier 3) also compiles every ASCII model to binary with cleanmodels before packing,
# and refuses to pack anything if a model fails its check or its compile. It needs cleanmodels, jq and perl, and
# the game's data (NWN_ROOT: the folder holding data/nwn_base.key) for stock supermodels and materials. A compiled
# model is kept in MODEL_CACHE by its content and everything it was compiled against, so the next build compiles
# only what changed. Without MODELS=compile, models are packed exactly as they are in git.
set -euo pipefail
cd "$(dirname "$0")"
MODELS=${MODELS:-ascii}
MODEL_CACHE=${MODEL_CACHE:-build/model-cache}

rm -rf build/hak build/tlk build/stage build/res
mkdir -p build/hak build/tlk

check_name() { # kind name: hak and talk table names are file names the server looks up in lowercase
  [[ $2 =~ ^[a-z0-9_]{1,16}$ ]] ||
    { echo "$1 name \"$2\": use at most 16 lowercase letters, digits and underscores" >&2; exit 1; }
}

for dir in haks/*/; do
  [ -d "$dir" ] || continue
  check_name hak "$(basename "$dir")"
  # The game keeps a file's name, before its extension, in 16 characters. A longer one cannot be found.
  while IFS= read -r file; do
    base=$(basename "$file"); base=${base%.*}
    [ ${#base} -le 16 ] || { echo "$file: the name \"$base\" has more than 16 characters" >&2; exit 1; }
  done < <(find "$dir" -type f)
done

if [ "$MODELS" = compile ]; then
  for tool in cleanmodels jq perl; do
    command -v "$tool" > /dev/null || { echo "MODELS=compile needs $tool on your PATH" >&2; exit 1; }
  done
  # A model's check is remembered for this version of cleanmodels and this build.sh, whose rules decide it.
  checked=$MODEL_CACHE/checked/$(cleanmodels --version | awk '{print $2}')-$(sha256sum "$0" | cut -c1-12)
  mkdir -p "$MODEL_CACHE/compile" "$checked"

  # 1. The game's data must be in reach, or stock supermodels and materials would silently not be found. A tiny
  # model whose supermodel only the game has must compile without a single warning.
  mkdir -p build/stage/canary
  printf '%s\n' 'newmodel zz_canary' 'setsupermodel zz_canary a_ba' 'classification CHARACTER' \
    'beginmodelgeom zz_canary' 'node dummy zz_canary' '  parent NULL' 'endnode' 'endmodelgeom zz_canary' \
    'donemodel zz_canary' > build/stage/canary/zz_canary.mdl
  canary=$(cleanmodels compile --overwrite build/stage/canary/zz_canary.mdl build/stage/canary/out/ 2>&1) || true
  grep -q '0 warnings, 0 errors' <<< "$canary" || {
    echo "the game's data is not in reach (NWN_ROOT=${NWN_ROOT:-unset}), so models would compile wrong:" >&2
    grep -E 'WARN|warning|ERROR' <<< "$canary" >&2; exit 1; }
  rm -rf build/stage/canary

  # 2. Every ASCII model (binary ones are packed as they are). A binary model starts with four zero bytes.
  mapfile -d '' models < <(find haks -type f -iname '*.mdl' -print0 |
    perl -0ne 'chomp; open my $f, "<", $_ or die "$_: $!"; read $f, my $b, 4; print "$_\0" if $b ne "\0\0\0\0"')
  echo "${#models[@]} ASCII models"

  # 3. Check them before anything is packed. A model that passed once is remembered by its checksum and not
  # checked again.
  declare -A sum
  while read -r hash path; do sum[$path]=$hash; done < <(printf '%s\0' "${models[@]}" | xargs -0 -r sha256sum)
  unchecked=()
  for m in "${models[@]}"; do
    marker=$checked/${sum[$m]}
    if [ -e "$marker" ]; then touch "$marker"; else unchecked+=("$m"); fi
  done
  if [ ${#unchecked[@]} -gt 0 ]; then
    # cleanmodels fails on an error, but a value it had to make up while reading (a short list of vertices, say) is
    # only a warning. Its JSON is read for both: a model it couldn't read, a made-up value, a check of severity
    # "error".
    report=$(printf '%s\0' "${unchecked[@]}" | xargs -0 cleanmodels check --dry-run --json 2> /dev/null) || true
    jq -e . > /dev/null 2>&1 <<< "$report" || { echo "cleanmodels could not check the models" >&2; exit 1; }
    bad=$(jq -r 'if type == "array" then .[] else . end | .file as $f |
      (.error // empty | "\($f): \(split("\n")[0])"), (.parse_warnings[]? | "\($f): \(.)"),
      (.checks[]? | select(.severity == "error") | .message)' <<< "$report")
    [ -z "$bad" ] || { echo "these models fail their check; nothing was packed:" >&2; echo "$bad" >&2; exit 1; }
    for m in "${unchecked[@]}"; do touch "$checked/${sum[$m]}"; done
  fi
  echo "checked $((${#models[@]} - ${#unchecked[@]})) unchanged models by their checksum, ${#unchecked[@]} with cleanmodels"

  # 4. One folder the compiler searches for supermodels, skeletons and materials from your own haks: hard links
  # to every model, .mtr and capart.2da. Always the same path, so the cache isn't fooled by a new hak folder.
  # Where two haks hold the same name, the first in alphabetical order is the one searched.
  mkdir -p build/res
  find haks -type f \( -iname '*.mdl' -o -iname '*.mtr' -o -iname 'capart.2da' \) -print0 | sort -z |
    while IFS= read -r -d '' f; do
      ln "$f" "build/res/$(basename "$f")" 2> /dev/null || echo "note: $f has the same name as a file in another hak" >&2
    done

  # 5. Compile each hak's ASCII models into a copy of the hak made of hard links: the copy's model links are
  # removed first and replaced by the compiled files, so nothing in your checkout is ever written to.
  compiled=0; cached=0
  for dir in haks/*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir"); dir=${dir%/}
    mine=(); for m in "${models[@]}"; do [[ $m == "$dir/"* ]] && mine+=("$m"); done
    [ ${#mine[@]} -gt 0 ] || continue
    out=build/stage/$name.out
    log=$(printf '%s\0' "${mine[@]}" | xargs -0 sh -c 'cleanmodels compile --cache-dir "$0" --resource-dir build/res \
      --overwrite "$@" "'"$out"'/"' "$MODEL_CACHE/compile" 2>&1) ||
      { echo "a model in $dir did not compile; nothing was packed:" >&2; grep -E 'ERROR|error' <<< "$log" >&2; exit 1; }
    mkdir -p build/stage
    cp -al "$dir" "build/stage/$name"
    for m in "${mine[@]}"; do
      rel=${m#"$dir/"}
      rm "build/stage/$name/$rel"
      mv "$out/$(basename "$m")" "build/stage/$name/$rel"
    done
    rm -rf "$out"   # what else the compiler wrote (a tile's walkmesh) is not used: your own .wok is packed
    compiled=$((compiled + ${#mine[@]}))
    # cleanmodels sums up "N files, M from the cache" for several files, and marks a single file "(from the cache)".
    cached=$((cached + $(awk '/^[0-9]+ files, [0-9]+ from the cache/ {s += $3} /\(from the cache\)$/ {s++}
      END {print s + 0}' <<< "$log")))
  done
  echo "compiled $compiled models, $cached of them from the cache"

  # The cache grows with every changed model: forget what no build has used for two weeks.
  cleanmodels cache prune --unused-for 14d "$MODEL_CACHE/compile" > /dev/null
  find "$MODEL_CACHE/checked" -mindepth 1 \( -type f -mtime +14 -o -type d -empty \) -delete
fi

for dir in haks/*/; do
  [ -d "$dir" ] || continue
  name=$(basename "$dir")
  src=$dir; [ -d "build/stage/$name" ] && src=build/stage/$name/
  nwn_erf -c -r 8 -f "build/hak/$name.hak" "$src"
  echo "packed build/hak/$name.hak ($(find "$dir" -type f | wc -l) files)"
done
rm -rf build/stage build/res

for json in tlk/*.tlk.json; do
  [ -e "$json" ] || continue
  name=$(basename "$json" .tlk.json)
  check_name tlk "$name"
  nwn_tlk -i "$json" -o "build/tlk/$name.tlk"
  echo "built build/tlk/$name.tlk"
done
