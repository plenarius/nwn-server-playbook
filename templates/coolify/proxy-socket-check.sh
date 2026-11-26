#!/usr/bin/env bash
# Restarts Coolify's proxy when it is holding an old copy of Docker's socket.
# A Docker package upgrade re-creates /var/run/docker.sock. A container that mounted the old one keeps it,
# and from then on the proxy can no longer see your applications. Run every minute by its timer.
set -euo pipefail
docker inspect coolify-proxy > /dev/null 2>&1 || exit 0     # no proxy on this machine
[ "$(docker inspect -f '{{.State.Running}}' coolify-proxy)" = true ] || exit 0
host=$(stat -c %i /var/run/docker.sock)
inside=$(docker exec coolify-proxy stat -c %i /var/run/docker.sock 2>/dev/null || echo none)
if [ "$host" != "$inside" ]; then
  echo "coolify-proxy holds an old Docker socket ($inside, now $host); restarting it"
  docker restart coolify-proxy > /dev/null
fi
