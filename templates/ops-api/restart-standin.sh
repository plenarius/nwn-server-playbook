#!/usr/bin/env bash
# A stand-in for your module's restart handler, to test the operations API's in-game countdown before your module
# has one (chapter 9, step 9). It speaks the API's restart contract (docs/contracts/restart.md in nwn-ops-api):
# it listens on the command channel, answers each request the way the game should, counts down, and at zero
# restarts the game's container, which is what a real handler's shutdown plus Docker's restart policy amount to.
#
# Run it on the game host, in the foreground, and stop it with Ctrl-C when you're done:
#   ./restart-standin.sh
# It is a test tool. Players see nothing from it, and it never belongs on a server people play on.
set -euo pipefail
PREFIX=${REDIS_PREFIX:-nwn:}

one() { # the one container of this compose service
  local ids; ids=$(docker ps -q --filter "label=com.docker.compose.service=$1")
  [ "$(printf '%s' "$ids" | grep -c .)" = 1 ] || { echo "expected one running '$1' container" >&2; exit 1; }
  echo "$ids"
}
redis=$(one redis)
game=$(one nwserver)
rcli() { docker exec -i "$redis" redis-cli "$@"; }

state=$(mktemp -d); trap 'kill $(cat "$state/pid" 2>/dev/null) 2>/dev/null; rm -rf "$state"' EXIT

reply() { # request_id status message
  [ -n "$1" ] || return 0
  rcli SET "${PREFIX}response:$1" "$(jq -cn --arg s "$2" --arg m "$3" '{status: $s, message: $m}')" EX 30 > /dev/null
  echo "replied $2: $3"
}
running() { [ -f "$state/pid" ] && kill -0 "$(cat "$state/pid")" 2>/dev/null; }

countdown() { # seconds
  sleep "$1"
  touch "$state/zero"
  echo "zero: shutting down (a real handler saves here, then NWNX_Administration_ShutdownServer)"
  sleep 2
  docker restart "$game" > /dev/null && echo "game container restarted"
  rm -f "$state/pid" "$state/zero"
}

echo "listening on ${PREFIX}cmd"
rcli SUBSCRIBE "${PREFIX}cmd" | while read -r kind && read -r channel && read -r payload; do
  [ "$kind" = message ] || continue
  if ! jq -e 'type == "object"' <<< "$payload" > /dev/null 2>&1; then echo "not a JSON object, ignored"; continue; fi
  cmd=$(jq -r '.cmd // ""' <<< "$payload")
  id=$(jq -r '.request_id // ""' <<< "$payload")
  echo "got $cmd on $channel"
  case $cmd in
    restart)
      seconds=$(jq -r '.args.seconds // empty' <<< "$payload")
      reason=$(jq -r '.args.reason // ""' <<< "$payload")
      [[ $seconds =~ ^[0-9]+$ ]] || { reply "$id" error "restart needs args.seconds"; continue; }
      if running; then reply "$id" error "A restart is already in progress."; continue; fi
      countdown "$seconds" & echo $! > "$state/pid"
      reply "$id" ok "Restart countdown started (${seconds}s, $reason)"
      ;;
    cancel_restart)
      if ! running; then reply "$id" error "No restart is in progress."
      elif [ -f "$state/zero" ]; then reply "$id" error "Too late to cancel: the server is shutting down."
      else kill "$(cat "$state/pid")"; rm -f "$state/pid"; reply "$id" ok "Restart cancelled."
      fi
      ;;
    *) reply "$id" error "Unknown command: $cmd" ;;
  esac
done
