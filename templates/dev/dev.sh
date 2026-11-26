#!/usr/bin/env bash
# Puts a module build on the dev server, takes it back, or says what is loaded (chapter 14).
#
#   ssh nwn@CONTROL "load pr-12-3f9c2ab" < mymodule.mod    the build, under a label that says where it came from
#   ssh nwn@CONTROL rollback                              the build that was loaded before this one
#   ssh nwn@CONTROL status                                what is loaded, when the database was copied, health
#
# A builder's key runs this and nothing else: its line in ~/.ssh/authorized_keys on the control host starts with
#   command="/home/nwn/dev/dev.sh \"$SSH_ORIGINAL_COMMAND\"",restrict
# You can also run it by hand on the control host:  ~/dev/dev.sh "load main-3f9c2ab" < mymodule.mod
#
# A load keeps the build it replaces, so rollback can put it back. When a new build doesn't become healthy, the
# old one goes back by itself. The live game is never touched: this only knows the dev server's containers.
set -euo pipefail
umask 022
cd "$(dirname "$0")"

request=${1:-}
case $request in
  status | rollback) verb=$request ;;
  load\ *)
    [[ $request =~ ^load\ ([A-Za-z0-9._-]{1,60})$ ]] || { echo "a label is letters, digits, . _ and -, at most 60 (got: ${request:0:80})" >&2; exit 2; }
    verb=load label=${BASH_REMATCH[1]} ;;
  *) echo "usage: load LABEL < module.mod | rollback | status  (got: ${request:0:60})" >&2; exit 2 ;;
esac

container() { # the one container of this compose service
  local ids; ids=$(docker ps -aq --filter "label=com.docker.compose.service=$1")
  [ "$(printf '%s' "$ids" | grep -c .)" = 1 ] || { echo "expected one '$1' container, found $(printf '%s' "$ids" | grep -c .)" >&2; exit 1; }
  echo "$ids"
}
game=$(container dev-nwserver)
module=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$game" | sed -n 's/^NWN_MODULE=//p')
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

case $verb in
  status)
    echo "loaded:      $(cat loaded.txt 2>/dev/null || echo 'nothing yet')"
    echo "before it:   $(cat loaded.previous.txt 2>/dev/null || echo 'nothing')"
    echo "database:    $(cat db-copied.txt 2>/dev/null || echo 'never copied from live')"
    echo "game:        $(health)"
    ;;

  load)
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
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
    if restart_and_wait; then
      echo "dev server is healthy with $label"
    elif [ -f "$mod.previous" ]; then
      echo "$label did not become healthy; putting the build before it back" >&2
      # The build before is current again, so there is nothing older to roll back to.
      cp -p "$mod.previous" "$mod" && mv -f loaded.previous.txt loaded.txt && rm -f "$mod.previous"
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
    restart_and_wait || { echo "the dev server did not become healthy; look at: docker logs --tail 50 $game" >&2; exit 1; }
    echo "dev server is healthy with $(cut -d' ' -f2 loaded.txt) again"
    ;;
esac
