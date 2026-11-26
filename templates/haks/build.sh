#!/usr/bin/env bash
# Builds your custom content from the files in this repository.
#   every folder in haks/         becomes  build/hak/<folder>.hak
#   every tlk/<name>.tlk.json     becomes  build/tlk/<name>.tlk
# Needs nwn_erf and nwn_tlk (the neverwinter.nim tools) on your PATH.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build/hak build/tlk
mkdir -p build/hak build/tlk

check_name() { # kind name: hak and talk table names are file names the server looks up in lowercase
  [[ $2 =~ ^[a-z0-9_]{1,16}$ ]] ||
    { echo "$1 name \"$2\": use at most 16 lowercase letters, digits and underscores" >&2; exit 1; }
}

for dir in haks/*/; do
  [ -d "$dir" ] || continue
  name=$(basename "$dir")
  check_name hak "$name"
  # The game keeps a file's name, before its extension, in 16 characters. A longer one cannot be found.
  while IFS= read -r file; do
    base=$(basename "$file"); base=${base%.*}
    [ ${#base} -le 16 ] || { echo "$file: the name \"$base\" has more than 16 characters" >&2; exit 1; }
  done < <(find "$dir" -type f)
  nwn_erf -c -r 8 -f "build/hak/$name.hak" "$dir"
  echo "packed build/hak/$name.hak ($(find "$dir" -type f | wc -l) files)"
done

for json in tlk/*.tlk.json; do
  [ -e "$json" ] || continue
  name=$(basename "$json" .tlk.json)
  check_name tlk "$name"
  nwn_tlk -i "$json" -o "build/tlk/$name.tlk"
  echo "built build/tlk/$name.tlk"
done
