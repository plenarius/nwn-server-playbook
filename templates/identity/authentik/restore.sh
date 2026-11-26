#!/usr/bin/env bash
# Puts Authentik's database back from a dump made by chapter 12's hook 20-site-dbs.sh (chapter 11, tier 3).
# Run it on the control host as a user who may use Docker:
#
#   restore.sh /var/backups/nwn-borg/site-authentik.sql
#
# It stops Authentik's server and worker, replaces the database with the dump, and starts them again. Everyone is
# signed out of Authentik (sessions are in the database, and come back as they were at the dump). The containers
# are found by their labels, so it works whatever Coolify named them. Authentik must have the same
# AUTHENTIK_SECRET_KEY as when the dump was made.
set -euo pipefail
dump=${1:?the dump file, such as /var/backups/nwn-borg/site-authentik.sql}
[ -s "$dump" ] && tail -n 6 "$dump" | grep -q 'PostgreSQL database dump complete' || { echo "$dump is not a complete dump" >&2; exit 1; }

db=$(docker ps -q --filter label=backup.name=authentik)
[ "$(printf '%s' "$db" | grep -c .)" = 1 ] || { echo "expected one running container labelled backup.name=authentik" >&2; exit 1; }
project=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$db")
apps=$(docker ps -q --filter "label=com.docker.compose.project=$project" --filter label=com.docker.compose.service=server
       docker ps -q --filter "label=com.docker.compose.project=$project" --filter label=com.docker.compose.service=worker)

echo "stopping Authentik's server and worker"
docker stop $apps > /dev/null
echo "replacing the database"
docker exec "$db" sh -c 'psql -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres -c "DROP DATABASE \"$POSTGRES_DB\" WITH (FORCE)" -c "CREATE DATABASE \"$POSTGRES_DB\""'
docker exec -i "$db" sh -c 'psql -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < "$dump" > /dev/null
echo "starting Authentik again"
docker start $apps > /dev/null
for i in $(seq 60); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' $apps | sort -u)" = healthy ] && { echo "Authentik is back"; exit 0; }
  sleep 5
done
echo "Authentik did not become healthy in 5 minutes: docker logs on the server container says why" >&2; exit 1
