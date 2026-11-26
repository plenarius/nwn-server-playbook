#!/usr/bin/env bash
# Puts a module build on the dev server, takes it back, or says what is loaded (chapter 14).
#
#   ssh nwn@CONTROL "load pr-12-3f9c2ab" < mymodule.mod    the build, under a label that says where it came from
#   ssh nwn@CONTROL rollback                              the build that was loaded before this one
#   ssh nwn@CONTROL status                                what is loaded, when the database was copied, health
#   ssh nwn@CONTROL "hak myarea" < myarea.hak             tier 3: a builder's hak, over the live ones, on the dev server only
#   ssh nwn@CONTROL "hak-remove myarea"                   tier 3: take it off again
#
# A builder's key runs this and nothing else: its line in ~/.ssh/authorized_keys on the control host starts with
#   command="/home/nwn/dev/dev.sh \"$SSH_ORIGINAL_COMMAND\"",restrict
# You can also run it by hand on the control host:  ~/dev/dev.sh "load main-3f9c2ab" < mymodule.mod
#
# A load keeps the build it replaces, so rollback can put it back. When a new build doesn't become healthy, the
# old one goes back by itself. The live game is never touched: this only knows the dev server's containers.
# Tier 3: when the dev game has an NWN_NWSYNCURL of its own, every load, rollback and hak runs dev-content.sh before
# the restart, and status.json in ~/dev/status says what runs, for the operations API.
set -euo pipefail
umask 022
cd "$(dirname "$0")"

request=${1:-}
case $request in
  status | rollback) verb=$request ;;
  hak\ * | hak-remove\ *)
    [[ $request =~ ^(hak|hak-remove)\ ([a-z0-9_]{1,16})$ ]] || { echo "a hak's name is 1 to 16 lowercase letters, digits and _ (got: ${request:0:80})" >&2; exit 2; }
    verb=${BASH_REMATCH[1]} hak=${BASH_REMATCH[2]} ;;
  load\ *)
    [[ $request =~ ^load\ ([A-Za-z0-9._-]{1,60})$ ]] || { echo "a label is letters, digits, . _ and -, at most 60 (got: ${request:0:80})" >&2; exit 2; }
    verb=load label=${BASH_REMATCH[1]} ;;
  *) echo "usage: load LABEL < module.mod | rollback | status | hak NAME < name.hak | hak-remove NAME  (got: ${request:0:60})" >&2; exit 2 ;;
esac

container() { # the one container of this compose service
  local ids; ids=$(docker ps -aq --filter "label=com.docker.compose.service=$1")
  [ "$(printf '%s' "$ids" | grep -c .)" = 1 ] || { echo "expected one '$1' container, found $(printf '%s' "$ids" | grep -c .)" >&2; exit 1; }
  echo "$ids"
}
game=$(container dev-nwserver)
setting() { docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$game" | sed -n "s/^$1=//p"; }
module=$(setting NWN_MODULE)
[[ $module =~ ^[A-Za-z0-9_]{1,16}$ ]] || { echo "the dev game has no usable NWN_MODULE setting" >&2; exit 1; }
mod=home/modules/$module.mod

health() { docker inspect -f '{{.State.Health.Status}}' "$game"; }
restart_and_wait() { # true when the game is healthy again within five minutes; false sooner if it keeps crashing
  local crashes; crashes=$(docker inspect -f '{{.RestartCount}}' "$game")
  docker restart -t 30 "$game" > /dev/null
  sleep 5
  for _ in $(seq 100); do
    [ "$(health)" = healthy ] && return 0
    # Docker counts the restarts it does after a crash (not ours above). Two means the module won't load.
    [ $(($(docker inspect -f '{{.RestartCount}}' "$game") - crashes)) -lt 2 ] || return 1
    sleep 3
  done
  return 1
}
record() { printf '%s %s sha256 %s\n' "$(date -u +%FT%TZ)" "$1" "$(sha256sum "$mod" | cut -d' ' -f1)" > loaded.txt; }

# Tier 3. The dev content, for the module now in place; nothing to do without an NWSync address of the dev game's own.
content() { [ -z "$(setting NWN_NWSYNCURL)" ] || ./dev-content.sh; }
dev_haks() { (cd content/hak 2> /dev/null && ls -- *.hak 2> /dev/null | sed 's/\.hak$//') || true; }
# What runs, as JSON, for the operations API (DEV_STATUS_FILE). Written by renaming, so it is never read half-written.
write_status() {
  mkdir -p status
  python3 - "$(cat loaded.txt 2> /dev/null)" "$(cat loaded.previous.txt 2> /dev/null)" "$(cat nwsync/latest 2> /dev/null)" \
    "$(dev_haks | paste -sd, -)" "$(cat db-copied.txt 2> /dev/null)" "$(health)" > status/status.json.new << 'PY'
import json, re, sys
from datetime import datetime, timezone
loaded, previous, content, haks, database, health = sys.argv[1:7]
parts = loaded.split()
label = parts[1] if len(parts) > 1 else None
m = re.search(r"-([0-9a-f]{7,40})$", label or "")
print(json.dumps({"label": label, "commit": m.group(1) if m else None, "sha256": parts[3] if len(parts) > 3 else None,
                  "loaded_at": parts[0] if parts else None, "previous": (previous.split() + [None, None])[1],
                  "content": content or None, "dev_haks": [h for h in haks.split(",") if h], "database": database or None,
                  "health": health, "updated_at": datetime.now(timezone.utc).isoformat(timespec="seconds")}))
PY
  chmod 644 status/status.json.new && mv -f status/status.json.new status/status.json
}
trap 'write_status 2> /dev/null || true' EXIT

case $verb in
  status)
    echo "loaded:      $(cat loaded.txt 2>/dev/null || echo 'nothing yet')"
    echo "before it:   $(cat loaded.previous.txt 2>/dev/null || echo 'nothing')"
    echo "database:    $(cat db-copied.txt 2>/dev/null || echo 'never copied from live')"
    echo "content:     $(cat nwsync/latest 2>/dev/null || echo 'the live content only')$(h=$(dev_haks | paste -sd' ' -); [ -z "$h" ] || echo ", dev haks: $h")"
    echo "game:        $(health)"
    ;;

  load)
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"; write_status 2> /dev/null || true' EXIT
    head -c 1073741825 > "$tmp/new.mod"
    [ "$(stat -c %s "$tmp/new.mod")" -le 1073741824 ] || { echo "the file is over 1 GB" >&2; exit 1; }
    [ "$(head -c 8 "$tmp/new.mod")" = "MOD V1.0" ] || { echo "that is not a module file" >&2; exit 1; }
    echo "received $label: $(stat -c %s "$tmp/new.mod") bytes, sha256 $(sha256sum "$tmp/new.mod" | cut -d' ' -f1)"
    mkdir -p home/modules
    if [ -f "$mod" ]; then
      cp -p "$mod" "$mod.previous"
      cp loaded.txt loaded.previous.txt 2> /dev/null || echo "(unknown)" > loaded.previous.txt
    fi
    cp "$tmp/new.mod" "$mod.new" && mv -f "$mod.new" "$mod"
    record "$label"
    if ! content; then
      # The module names a hak that nobody has, or the dev content could not be written: the build before goes back.
      echo "the dev content for $label could not be made, so it is not loaded" >&2
      if [ -f "$mod.previous" ]; then
        cp -p "$mod.previous" "$mod" && mv -f loaded.previous.txt loaded.txt && rm -f "$mod.previous"; content || true
      else
        rm -f "$mod" loaded.txt
      fi
      exit 1
    fi
    if restart_and_wait; then
      echo "dev server is healthy with $label"
    elif [ -f "$mod.previous" ]; then
      echo "$label did not become healthy; putting the build before it back" >&2
      # The build before is current again, so there is nothing older to roll back to.
      cp -p "$mod.previous" "$mod" && mv -f loaded.previous.txt loaded.txt && rm -f "$mod.previous"
      content || true
      restart_and_wait && echo "dev server is back on $(cut -d' ' -f2 loaded.txt)" >&2
      echo "look at what went wrong with: docker logs --tail 50 $game" >&2
      exit 1
    else
      echo "$label did not become healthy, and there is no earlier build to go back to; look at: docker logs --tail 50 $game" >&2
      exit 1
    fi
    ;;

  rollback)
    [ -f "$mod.previous" ] && [ -f loaded.previous.txt ] || { echo "there is no earlier build to go back to" >&2; exit 1; }
    # Swap the two, so that a second rollback undoes the first.
    mv -f "$mod" "$mod.swap" && mv -f "$mod.previous" "$mod" && mv -f "$mod.swap" "$mod.previous"
    mv -f loaded.txt loaded.swap.txt && mv -f loaded.previous.txt loaded.txt && mv -f loaded.swap.txt loaded.previous.txt
    content
    restart_and_wait || { echo "the dev server did not become healthy; look at: docker logs --tail 50 $game" >&2; exit 1; }
    echo "dev server is healthy with $(cut -d' ' -f2 loaded.txt) again"
    ;;

  hak)
    [ -n "$(setting NWN_NWSYNCURL)" ] || { echo "the dev game has no NWN_NWSYNCURL of its own, so it can't hand out a hak (chapter 14, tier 3)" >&2; exit 1; }
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"; write_status 2> /dev/null || true' EXIT
    head -c 2147483649 > "$tmp/new.hak"
    [ "$(stat -c %s "$tmp/new.hak")" -le 2147483648 ] || { echo "the file is over 2 GB" >&2; exit 1; }
    [ "$(head -c 8 "$tmp/new.hak")" = "HAK V1.0" ] || { echo "that is not a hak file" >&2; exit 1; }
    echo "received $hak.hak: $(stat -c %s "$tmp/new.hak") bytes, sha256 $(sha256sum "$tmp/new.hak" | cut -d' ' -f1)"
    mkdir -p content/hak
    [ ! -f "content/hak/$hak.hak" ] || cp -p "content/hak/$hak.hak" "$tmp/old.hak"
    cp "$tmp/new.hak" "content/hak/$hak.hak.new" && mv -f "content/hak/$hak.hak.new" "content/hak/$hak.hak"
    if content && restart_and_wait; then
      echo "dev server is healthy with $hak.hak"
    else
      echo "the dev server did not take $hak.hak; taking it back off" >&2
      if [ -f "$tmp/old.hak" ]; then mv -f "$tmp/old.hak" "content/hak/$hak.hak"; else rm -f "content/hak/$hak.hak"; fi
      content || true
      restart_and_wait || true
      echo "look at what went wrong with: docker logs --tail 50 $game" >&2
      exit 1
    fi
    ;;

  hak-remove)
    [ -f "content/hak/$hak.hak" ] || { echo "the dev server has no hak of its own called $hak" >&2; exit 1; }
    rm -f "content/hak/$hak.hak"
    content && restart_and_wait || { echo "the dev server did not become healthy; look at: docker logs --tail 50 $game" >&2; exit 1; }
    echo "dev server is healthy without its own $hak.hak"
    ;;
esac
