# Playbook 13, tier 3. The game's numbers, its logs and traces, in one place

For an agent. The chapter for people is [`chapters/13-monitoring.md`](../chapters/13-monitoring.md), section
"Tier 3". Follow the steps in order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `GAME` | The game host's public address | none: a person gives it |
| `CONTROL` | The control host's public address | none: a person gives it |
| `CONTROL_WG` | The control host's private address | `10.77.0.1` |
| `DEPLOY_USER` | The deploy user on both machines | `nwn` |
| `OPS_API` | `yes` if chapter 9's operations API runs on the control host | none: a person says |

Secrets: Grafana's admin password, made on the control host in `~/monitoring/secrets/grafana-admin-password`; the
alert webhook, placed by the person in `~/monitoring/secrets/alert-webhook`. Never read or print either. The person
reads the password themselves.

## Preconditions

```sh
ssh $DEPLOY_USER@$CONTROL "test -e ~/monitoring && echo 'monitoring exists' || echo 'no monitoring'; ping -c 2 -q 10.77.0.2 | grep -o ' 0% packet loss'; free -m | awk '/^Mem/{print \$7\" MB available\"}'; systemctl is-active nwn-watchdog.timer"
ssh $DEPLOY_USER@$GAME 'cd game && grep -c "^NWNX_METRICS_INFLUXDB_SKIP=n" .env; grep ^COMPOSE_FILE .env; docker inspect -f "{{.State.Health.Status}}" game-nwserver-1'
```

Success: `no monitoring`, `0% packet loss`, at least 900 MB available, `active`; `0`, a `COMPOSE_FILE` line,
`healthy`. If `monitoring exists` or the first number on the game host is `1`, stop and ask. Less than 900 MB
available: stop and ask (the stack needs about 650 MB).

## Steps

### 1. The stack's files and folders

```sh
scp -r templates/monitoring $DEPLOY_USER@$CONTROL:monitoring
ssh $DEPLOY_USER@$CONTROL "cd monitoring && sudo install -d -o 1500 -g 1500 data/influxdb && sudo install -d -o 10001 -g 10001 data/loki data/tempo && sudo install -d -o 472 -g 472 data/grafana && sudo install -d -m 750 -g 472 secrets && sudo sh -c 'umask 027; openssl rand -base64 18 > secrets/grafana-admin-password; chgrp 472 secrets/grafana-admin-password' && ([ $CONTROL_WG = 10.77.0.1 ] || echo MONITOR_ADDRESS=$CONTROL_WG > .env) && sudo stat -c '%a %g %s' secrets/grafana-admin-password"
```

Success: `640 472` and a size over 0.

### 2. The webhook, placed by the person

Ask the person to run this on their computer, paste the same webhook address as for tier 2, and tell you when it
returns:

```sh
ssh -t DEPLOY_USER@CONTROL 'read -rs -p "Webhook address: " u; echo; printf "%s\n" "$u" | sudo sh -c "umask 027; cat > monitoring/secrets/alert-webhook; chgrp 472 monitoring/secrets/alert-webhook"; echo saved'
```

Then:

```sh
ssh $DEPLOY_USER@$CONTROL 'sudo stat -c "%a %g %s" monitoring/secrets/alert-webhook'
```

Success: `640 472` and a size over 0.

### 3. Start it

```sh
ssh $DEPLOY_USER@$CONTROL 'cd monitoring && docker compose up -d 2>&1 | tail -1; for i in $(seq 30); do [ "$(docker compose ps --format "{{.State}}" | grep -c running)" = 4 ] && break; sleep 3; done; docker compose ps --format "{{.Service}} {{.State}}"; docker compose exec -T influxdb influx -execute "SHOW RETENTION POLICIES ON nwn" | awk "NR>2{print \$1, \$2, \$NF}"'
```

Success: four services `running`; `raw 336h0m0s true` and `rollup_1m 4320h0m0s false`.

### 4. Nothing public

```sh
ssh $DEPLOY_USER@$CONTROL "sudo ss -ltnup | grep -E ':(3000|3100|4318|8089) ' | awk '{print \$1, \$5}'"
for p in 3000 3100 3200 4317 4318 8086; do timeout 4 bash -c "</dev/tcp/$CONTROL/$p" 2>/dev/null && echo "$p OPEN" || echo "$p closed"; done
```

Success: exactly `tcp 127.0.0.1:3000`, `tcp $CONTROL_WG:3100`, `tcp $CONTROL_WG:4318`, `udp $CONTROL_WG:8089`; then
six `closed`. Any `OPEN` or `0.0.0.0`: run `docker compose down` in `~/monitoring` and stop and ask.

### 5. The game host's settings and the log shipper

```sh
scp templates/game/.env.metrics.example templates/game/compose.logs.yaml templates/game/logs.alloy $DEPLOY_USER@$GAME:game/
ssh $DEPLOY_USER@$GAME "cd game && cat .env.metrics.example >> .env && rm .env.metrics.example && sed -i 's|^NWNX_METRICS_INFLUXDB_HOST=.*|NWNX_METRICS_INFLUXDB_HOST=$CONTROL_WG|' .env && grep -q compose.logs.yaml .env || sed -i 's|^COMPOSE_FILE=.*|&:compose.logs.yaml|' .env; grep -E '^(COMPOSE_FILE|NWNX_METRICS_INFLUXDB_HOST)=' .env; [ $CONTROL_WG = 10.77.0.1 ] || echo LOKI_URL=http://$CONTROL_WG:3100/loki/api/v1/push >> .env"
```

Success: the `COMPOSE_FILE` line ending in `:compose.logs.yaml`, and `NWNX_METRICS_INFLUXDB_HOST=$CONTROL_WG`.

### 6. Restart the game, with the person's yes

**Stop and ask** the person for a time to restart the game: the plugins load only at start. With their yes:

```sh
ssh $DEPLOY_USER@$CONTROL 'sudo -u nwn-watchdog nwn-watchdog pause 10'
ssh $DEPLOY_USER@$GAME 'cd game && docker compose up -d 2>&1 | tail -1; for i in $(seq 60); do s=$(docker inspect -f "{{.State.Health.Status}}" game-nwserver-1); [ "$s" = healthy ] && break; sleep 3; done; echo "game $s"; docker compose logs nwserver 2>&1 | grep -o "Loaded plugin .*NWNX_\(Profiler\|Metrics_InfluxDB\|ThreadWatchdog\|ServerLogRedirector\)" | sort -u; docker compose ps --format "{{.Service}} {{.State}}" | grep alloy'
ssh $DEPLOY_USER@$CONTROL 'sudo -u nwn-watchdog nwn-watchdog resume'
```

Success: `game healthy`, four `Loaded plugin` lines, `alloy running`, `resumed`.

### 7. Traces, if `OPS_API` is yes

The operations API runs in Coolify. Ask the person to add these two variables to its service in Coolify and
redeploy it (or give you the Coolify steps from chapter 9's playbook to do it):

```
OTEL_EXPORTER_OTLP_ENDPOINT=http://CONTROL_WG:4318
OTEL_SERVICE_NAME=nwn-ops-api
```

Then:

```sh
ssh $DEPLOY_USER@$CONTROL 'docker logs $(docker ps -q --filter name=ops-api | head -1) 2>&1 | grep -o "Tracing on: .*"'
```

Success: `Tracing on: spans to http://$CONTROL_WG:4318`. Never set any `OTEL_INSTRUMENTATION_HTTP_CAPTURE_HEADERS_*`.

## Verify

After two minutes. Numbers, logs and (if `OPS_API`) traces have arrived, and Grafana sees all three, through its
own API on the control host (the password is read into a variable there, never printed):

```sh
ssh $DEPLOY_USER@$CONTROL 'cd monitoring; docker compose exec -T influxdb influx -database nwn -execute "SELECT count(*) FROM \"NWNX_Profiler.GameTickRate\" WHERE time > now() - 1m" | tail -1; curl -s -G http://'$CONTROL_WG':3100/loki/api/v1/query_range --data-urlencode "query={service=\"nwserver\"}" --data-urlencode since=10m --data-urlencode limit=5 | grep -o "\"service\":\"nwserver\"" | head -1; P=$(sudo cat secrets/grafana-admin-password); for u in nwn-influxdb nwn-loki nwn-tempo; do curl -s -u "admin:$P" http://127.0.0.1:3000/api/datasources/uid/$u/health | grep -o "\"status\":\"OK\""; done; curl -s -u "admin:$P" "http://127.0.0.1:3000/api/search?query=Game%20server" | grep -o "\"title\":\"Game server\""; curl -s -u "admin:$P" http://127.0.0.1:3000/api/v1/provisioning/alert-rules | grep -o "\"title\":\"Game stalled\""; unset P'
```

Success: a count of about 60; `"service":"nwserver"`; three `"status":"OK"`; `"title":"Game server"`;
`"title":"Game stalled"`. Then ask the person to open the dashboard (chapter, step 16) and say what they see.

If `OPS_API`, traces:

```sh
ssh $DEPLOY_USER@$CONTROL 'docker run --rm --network monitoring_default curlimages/curl:8.11.1 -s "http://tempo:3200/api/search?limit=3" | grep -o "\"rootServiceName\":\"nwn-ops-api\"" | head -1'
```

Success: `"rootServiceName":"nwn-ops-api"`, after something has called the API.

## Roll back

```sh
ssh $DEPLOY_USER@$GAME "cd game && sed -i 's|:compose.logs.yaml||' .env && docker compose rm -sf alloy >/dev/null 2>&1; rm -f compose.logs.yaml logs.alloy; sudo rm -rf alloy-data; grep -c compose.logs .env"
ssh $DEPLOY_USER@$CONTROL 'cd monitoring && docker compose down 2>&1 | tail -1'
```

Success: `0`, then the containers removed. The plugin lines stay in the game host's `.env`, harmless (the
numbers go nowhere); taking them out needs another restart, so ask. The data and secrets stay in
`~/monitoring` on the control host; removing that folder deletes the history of the numbers and logs, and is the
person's call. If `OPS_API`, the person removes the two variables in Coolify.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- restarting the game (step 6), or any restart of it to test something;
- reading, printing or replacing Grafana's password or the webhook address;
- a port listening on `0.0.0.0` or a public address, or `OPEN` from outside;
- `~/monitoring` already there, or the plugins already switched on;
- less memory on the control host than the stack needs;
- removing `~/monitoring/data` or any retention policy, or shortening retention;
- changing the operations API's variables in Coolify, unless the person asked you to;
- setting `OTEL_INSTRUMENTATION_HTTP_CAPTURE_HEADERS_*` anywhere.
