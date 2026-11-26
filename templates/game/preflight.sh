#!/usr/bin/env bash
# Looks at everything a release depends on, changes nothing, and says what it found (chapter 16, tier 2).
#
#   sudo ./preflight.sh
#
# Run it from the game folder, before a release and as often as you like. Each line starts with "ok" or "LOOK",
# and the last line says whether anything needs a look. Exit status 0 when nothing does, 1 otherwise.
# It reads: the live and staging games, ~/incoming, the staged module, the migrations waiting, the backups (here
# and off-site), the download address and the disk. It never stops, starts or writes anything except the
# migrations ledger table, which ./migrate.sh status makes if it isn't there yet.
set -uo pipefail
cd "$(dirname "$0")"

owner=$(stat -c %U .)
home=$(getent passwd "$owner" | cut -d: -f6)
incoming=$home/incoming
staging=${STAGING_DIR:-$home/staging}
looks=0
ok() { echo "ok    $*"; }
look() { echo "LOOK  $*"; looks=$((looks + 1)); }

one() { # the one container of a compose service, or nothing
  local ids; ids=$(docker ps -aq --filter "label=com.docker.compose.service=$1")
  [ "$(printf '%s' "$ids" | grep -c .)" = 1 ] && echo "$ids"
}
health() { docker inspect -f '{{.State.Health.Status}}' "$1" 2>/dev/null; }
setting() { docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$1" | sed -n "s/^$2=//p"; }
age_hours() { echo $(( ($(date +%s) - $1) / 3600 )); }

# The live game.
game=$(one nwserver)
if [ -z "$game" ]; then
  look "the live game: expected one nwserver container, found $(docker ps -aq --filter label=com.docker.compose.service=nwserver | grep -c .)"
else
  [ "$(health "$game")" = healthy ] && ok "the live game is healthy" || look "the live game is $(health "$game")"
  module=$(setting "$game" NWN_MODULE)
fi
module=${module:-}

# The staging game, and what it runs.
sgame=$(one staging-nwserver)
staged_sum=""
if [ -z "$sgame" ]; then
  echo "--    no staging game on this host"
else
  [ "$(health "$sgame")" = healthy ] && ok "staging is healthy" || look "staging is $(health "$sgame")"
  if [ -f "$staging/staged.txt" ]; then
    read -r when version _ staged_sum _ < "$staging/staged.txt"
    ok "staging runs $version, staged $when"
    [ -n "$module" ] && [ -f "$staging/home/modules/$module.mod" ] &&
      [ "$(sha256sum < "$staging/home/modules/$module.mod" | cut -d' ' -f1)" != "$staged_sum" ] &&
      look "staging's module file isn't the one staged.txt names"
  else
    look "nothing has been staged yet"
  fi
fi

# What is waiting in ~/incoming.
shopt -s nullglob
files=("$incoming"/*.mod "$incoming"/*.hak "$incoming"/*.tlk)
if [ ${#files[@]} -eq 0 ] && [ ! -d "$incoming/migrations" ]; then
  look "nothing in $incoming to release"
fi
for f in "${files[@]}"; do
  case $f in
    *.mod)
      [ "$(basename "$f" .mod)" = "$module" ] || look "$(basename "$f") isn't the module the game loads ($module.mod)"
      sum=$(sha256sum < "$f" | cut -d' ' -f1)
      if [ -z "$staged_sum" ]; then look "$(basename "$f") waits, and staging can't vouch for it"
      elif [ "$sum" = "$staged_sum" ]; then ok "$(basename "$f") waits, the same file staging runs ($version)"
      else look "$(basename "$f") waits, but it is not the file staging runs: copy staging's instead"; fi ;;
    *) ok "$(basename "$f") waits" ;;
  esac
done

# Migrations waiting.
if [ -d "$incoming/migrations" ]; then
  if st=$(MIGRATIONS=$incoming/migrations ./migrate.sh status 2>&1); then
    ok "migrations: $(grep -E '^[0-9]+ applied' <<< "$st")"
  else
    look "migrations: $(grep -m1 -E 'PROBLEM|could not' <<< "$st")"
  fi
fi

# Backups: the newest one here, and the newest off-site one (chapter 12, tier 2) if this host has borg.
newest=$(find backups -mindepth 1 -maxdepth 1 -type d -name '[0-9]*-[0-9]*' 2>/dev/null | sort | tail -n 1)
if [ -z "$newest" ]; then look "no backup here yet"
else
  h=$(age_hours "$(stat -c %Y "$newest")")
  [ "$h" -le 26 ] && ok "newest backup here: $newest, $h h old" || look "newest backup here is $h h old: is the nightly timer running?"
fi
if command -v nwn-borg-backup > /dev/null; then
  if last=$(nwn-borg-backup borg list --last 1 --format '{time}' 2> /dev/null) && [ -n "$last" ]; then
    h=$(age_hours "$(date -d "$last" +%s)")
    [ "$h" -le 26 ] && ok "newest off-site backup: $h h old" || look "newest off-site backup is $h h old"
  else
    look "the off-site backups can't be listed: is the storage reachable?"
  fi
fi

# The download address: what it names, and what the game hands out.
if [ -n "$game" ] && url=$(setting "$game" NWN_NWSYNCURL) && [ -n "$url" ]; then
  latest=$(curl -fsS -m 10 "$url/latest" 2> /dev/null)
  live=$(docker logs "$game" 2>&1 | grep -a "now advertising" | tail -n 1 | grep -o '[0-9a-f]\{40\}')
  if [ -z "$latest" ]; then
    look "$url/latest doesn't answer: the game couldn't start again now"
  elif [ "$latest" = "$live" ]; then
    ok "downloads: $url names $latest, the version the game hands out"
  else
    look "downloads: $url names $latest, but the game hands out ${live:-nothing it said}: a restart now would mismatch"
  fi
  if [ -n "$sgame" ] && surl=$(setting "$sgame" NWN_NWSYNCURL) && [ -n "$surl" ]; then
    slatest=$(curl -fsS -m 10 "$surl/latest" 2> /dev/null)
    slive=$(docker logs "$sgame" 2>&1 | grep -a "now advertising" | tail -n 1 | grep -o '[0-9a-f]\{40\}')
    if [ -z "$slatest" ]; then look "$surl/latest doesn't answer: staging couldn't start again now"
    elif [ "$slatest" = "$slive" ]; then ok "staging hands out $slive"
    else look "staging hands out ${slive:-nothing it said}, but its address names $slatest: stage again"; fi
  fi
fi

# Room on the disk, and the way back.
use=$(df --output=pcent . | tail -n 1 | tr -dc 0-9)
[ "$use" -lt 85 ] && ok "disk $use% full" || look "disk $use% full"
last=$(find releases -mindepth 1 -maxdepth 1 -type d ! -name '*.undone' 2>/dev/null | sort | tail -n 1)
[ -n "$last" ] && ok "release.sh --undo would put back $last" || echo "--    no earlier release to undo yet"

if [ $looks = 0 ]; then echo "nothing to look at: ready when you are"; else echo "$looks thing(s) to look at above"; exit 1; fi
