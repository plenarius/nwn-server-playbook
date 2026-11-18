# Playbook 2, tier 2. Your website behind Cloudflare's proxy

For an agent. The chapter for people is [`chapters/02-dns.md`](../chapters/02-dns.md), section "Tier 2". Follow the
steps in order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `SITE_HOST` | The website's name, such as `www.example.org`, made by `cf-record.sh` and served by Coolify on the control host | none: a person gives it |
| `CONTROL` | The control host's public address | none: a person gives it |
| `DEPLOY_USER` | The deploy user there | `nwn` |

Secrets, placed in the environment by a person, never printed:

- `CF_API_TOKEN` and `CF_ZONE_ID`, as in playbook 2;
- optionally `CF_SETTINGS_TOKEN`, a token that may **read** zone settings. Without it, the person checks step 1 in
  the dashboard.

## Preconditions

```sh
templates/dns/cf-record.sh show $SITE_HOST
curl -s -m 10 -o /dev/null -w "%{http_code}\n" --resolve $SITE_HOST:443:$CONTROL https://$SITE_HOST/
```

Success: one A record holding `CONTROL`, `dns-only`, with the comment `nwn-server-playbook`; then `200`. A proxied
record, another address, or no comment: stop and ask.

## Steps

### 1. Read the zone settings

```sh
for s in ssl always_use_https rocket_loader early_hints email_obfuscation; do printf '%s: ' $s; curl -s -H @<(printf 'Authorization: Bearer %s\n' "$CF_SETTINGS_TOKEN") "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/settings/$s" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["result"]["value"] if d.get("success") else "could not read")'; done
```

Success: `ssl: strict`, then `off` four times. Never change a zone setting yourself: they cover the whole domain.
If any differs, or `could not read`, tell the person which, and the chapter's step 9, and wait until they say it's
done; then run this step again (or take their word for it if there is no settings token).

### 2. Coolify's proxy trusts Cloudflare

Make the two lines:

```sh
RANGES=$({ curl -s https://www.cloudflare.com/ips-v4; echo; curl -s https://www.cloudflare.com/ips-v6; } | grep . | paste -sd,)
printf "      - '--entrypoints.http.forwardedHeaders.trustedIPs=%s'\n      - '--entrypoints.https.forwardedHeaders.trustedIPs=%s'\n" "$RANGES" "$RANGES"
```

Coolify has no API for its proxy. **Give the person the two lines** and the chapter's step 10: on the control host's
**Proxy** page, **Configuration**, add them after `- '--entrypoints.https.address=:443'`, **Save changes**, then
**Restart Proxy**. Wait until they say it's done. Then:

```sh
ssh $DEPLOY_USER@$CONTROL "docker inspect -f '{{join .Args \"\n\"}}' coolify-proxy | grep -c forwardedHeaders.trustedIPs"
curl -s -m 10 -o /dev/null -w "%{http_code}\n" --resolve $SITE_HOST:443:$CONTROL https://$SITE_HOST/
```

Success: `2`, then `200`.

### 3. Switch the proxy on

**Ask first**: the name's answers change to Cloudflare's addresses, for everyone. After the yes:

```sh
templates/dns/cf-record.sh proxy $SITE_HOST on
sleep 60
curl -sI -m 10 https://$SITE_HOST/ | grep -i -E '^(HTTP|server|cf-cache-status)' | tr -d '\r'
echo | openssl s_client -connect $CONTROL:443 -servername $SITE_HOST 2>/dev/null | openssl x509 -noout -issuer
curl -s -m 10 -o /dev/null -w "plain http: %{http_code} %{redirect_url}\n" http://$SITE_HOST/
```

Success: `now A $SITE_HOST ... proxied`; then `200`, `server: cloudflare` and `cf-cache-status: DYNAMIC`; an issuer
naming Let's Encrypt; and a `302` or `301` to `https://$SITE_HOST/`. A `52x` status means Cloudflare can't reach the
machine properly: take the way back and report.

## Verify

The real visitor's address reaches the site:

```sh
MARK=agent-check-$(date +%s)
curl -s -m 10 -o /dev/null https://$SITE_HOST/?$MARK; sleep 3
ssh $DEPLOY_USER@$CONTROL "for c in \$(docker ps -q); do docker logs --since 2m \$c 2>&1 | grep $MARK; done" | grep -o '"[^"]*"$'
curl -s -m 10 https://api.ipify.org; echo
```

Success: a quoted list whose second-to-last entry is the address on the last line (yours), and whose last entry is
Cloudflare's. A list with only one address means step 2 isn't in effect: report it.

If the person's site writes no access log, skip this check and say so.

## Roll back

```sh
templates/dns/cf-record.sh proxy $SITE_HOST off
```

Success: `now A $SITE_HOST ... dns-only`. The trust lines can stay: they change nothing while no request comes
through Cloudflare.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- step 3, always;
- any change to a zone setting, a cache rule, a page rule or a firewall rule;
- proxying any name other than `SITE_HOST`, and above all the game's name or the downloads' name;
- a `52x` answer after step 3.
