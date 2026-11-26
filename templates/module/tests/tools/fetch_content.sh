#!/usr/bin/env bash
# Downloads the haks and the talk table your game hands out, from your download address over HTTPS, the way a
# player's game does, checks every file, and packs them again as the haks the test server loads (chapter 6,
# tier 2, step 16).
#
#   fetch_content.sh --which URL          prints the version to test with (version=...) and where it is from
#   fetch_content.sh URL OUT [VERSION]    downloads it into OUT/hak and OUT/tlk
#
# e.g. fetch_content.sh https://nwsync.example.org tests/.content
#
# Which version: the staged one, if the address has one under /staging (chapter 7, tier 2 stages content for the
# staging copy there), because that is what your next release will carry; otherwise the one players get now.
# If OUT already holds the version (GitHub's cache), nothing is downloaded. The version must have been written
# with --write-origins (chapter 7), which lists the hak each file came from. Needs curl and the neverwinter.nim
# tools (chapter 6, step 1).
set -euo pipefail

# The version a "latest" names: empty if there is none (404), an error if the address doesn't answer.
latest() {
  local body code
  body=$(mktemp); code=$(curl -sS -m 30 -o "$body" -w '%{http_code}' "$1/latest" 2>/dev/null) || code=000
  case $code in
    200) grep -oE '^[0-9a-f]{40}' "$body" || { echo "$1/latest is not a version" >&2; rm -f "$body"; return 1; } ;;
    404) ;;
    *) echo "could not read $1/latest (HTTP $code): is the download address up?" >&2; rm -f "$body"; return 1 ;;
  esac
  rm -f "$body"
}

if [ "${1:-}" = "--which" ]; then
  url=${2:?give the download address}; url=${url%/}
  staged=$(latest "$url/staging")
  if [ -n "$staged" ]; then echo "version=$staged"; echo "from=$url/staging (staged)"; exit 0; fi
  live=$(latest "$url")
  [ -n "$live" ] || { echo "$url has no latest: nothing has been published there" >&2; exit 1; }
  echo "version=$live"; echo "from=$url (what players get)"
  exit 0
fi

url=${1:?give the download address}; url=${url%/}
out=${2:?give the folder to put the content in}
version=${3:-$("$0" --which "$url" | sed -n 's/^version=//p')}
[[ $version =~ ^[0-9a-f]{40}$ ]] || { echo "not a version: $version" >&2; exit 1; }
if [ "$(cat "$out/version" 2>/dev/null)" = "$version" ]; then
  echo "content $version: already here, $(ls "$out/hak" | wc -l) haks"
  exit 0
fi

rm -rf "$out"; mkdir -p "$out/hak" "$out/tlk"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
curl -fsS -m 60 -o "$work/manifest" "$url/manifests/$version" ||
  { echo "could not download the manifest of $version from $url" >&2; exit 1; }
curl -fs -m 60 -o "$work/origin" "$url/manifests/$version.origin" ||
  { echo "$url has no list of haks for $version: write your content with --write-origins (chapter 7) and publish it again" >&2; exit 1; }

# The manifest lists each file as: checksum, size, type, name. Download each checksum once, eight at a time.
nwn_nwsync_print "$work/manifest" 2>/dev/null | grep -E '^[0-9a-f]{40} ' | awk '{print $1, $3, $4}' > "$work/files"
[ -s "$work/files" ] || { echo "the manifest of $version lists no files" >&2; exit 1; }
awk '{print $1}' "$work/files" | sort -u |
  sed -E "s|^((..)(..).*)|url = \"$url/data/sha1/\2/\3/\1\"\noutput = \"$work/data/\1\"|" > "$work/curl.cfg"
curl -fsS --retry 3 --create-dirs --parallel --parallel-max 8 -K "$work/curl.cfg" ||
  { echo "some files of $version could not be downloaded from $url" >&2; exit 1; }

# The origin list says which hak (or talk table) each file came from: a line naming the container, then its
# files, one per line, each after a tab.
awk -F'\t' 'NR == FNR { if (/^[^\t]/) c = $0; else where[$2] = c; next }
  { split($0, f, " "); file = f[3] "." f[2]; c = where[file]
    if (c ~ /\.hak$/) { sub(/.*\//, "", c); sub(/\.hak$/, "", c); print f[1], "res/" c, file }
    else if (c ~ /\.tlk$/) print f[1], "tlk", file
    else { print file ": from \"" c "\", which is not a hak or a talk table" > "/dev/stderr"; exit 1 } }' \
  "$work/origin" "$work/files" > "$work/plan"
while read -r sha dir file; do
  mkdir -p "$work/$dir"
  nwn_compressedbuf -d NSYC -i "$work/data/$sha" -o "$work/$dir/$file"
  [ "$(sha1sum < "$work/$dir/$file" | cut -c1-40)" = "$sha" ] ||
    { echo "$file does not match its checksum in the manifest" >&2; exit 1; }
done < "$work/plan"

for dir in "$work"/res/*/; do
  [ -d "$dir" ] || continue
  nwn_erf --quiet -c -f "$out/hak/$(basename "$dir").hak" "$dir"
done
[ ! -d "$work/tlk" ] || mv "$work"/tlk/*.tlk "$out/tlk/"
echo "$version" > "$out/version"
echo "content $version: $(wc -l < "$work/files") files checked, $(ls "$out/hak" | wc -l) haks, $(ls "$out/tlk" | wc -l) talk tables"
