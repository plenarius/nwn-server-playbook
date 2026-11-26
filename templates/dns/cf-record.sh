#!/usr/bin/env bash
# One address record at Cloudflare DNS: show it, create it or delete it.
#
#   cf-record.sh show   NAME            NAME is the full name, e.g. game.example.org
#   cf-record.sh create NAME ADDRESS    ADDRESS is an IPv4 address; this makes an A record
#   cf-record.sh delete NAME
#
# Needs two settings in the environment, put there by a person:
#   CF_API_TOKEN   a token that may edit DNS in this one zone and nothing else
#   CF_ZONE_ID     the zone's id (Cloudflare dashboard, the domain's Overview page)
# Optional: TTL in seconds (default 300).
#
# Records it creates are DNS-only (not proxied) and carry the comment "nwn-server-playbook".
# "create" refuses a name that already has a record. "delete" refuses a record without that comment,
# so it can only remove what it made. The token is never printed.
set -euo pipefail

: "${CF_API_TOKEN:?set CF_API_TOKEN}" "${CF_ZONE_ID:?set CF_ZONE_ID}"
TTL=${TTL:-300}
TAG=nwn-server-playbook
API="https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records"

api() { # method url [json]. The token goes in through a file descriptor, not the command line.
  curl -sS -X "$1" -H @<(printf 'Authorization: Bearer %s\n' "$CF_API_TOKEN") \
    -H 'Content-Type: application/json' ${3:+-d "$3"} "$2"
}

# Reads an API answer on stdin. Prints one line per record: TYPE NAME ADDRESS MODE TTL ID COMMENT.
# On an API error it prints only the error messages and fails.
records() {
  python3 -c '
import json, sys
d = json.load(sys.stdin)
if not d.get("success"):
    sys.exit("Cloudflare said: " + "; ".join(e.get("message", "?") for e in d.get("errors", [])))
r = d["result"]
for x in (r if isinstance(r, list) else [r]):
    if "type" in x:
        print(x["type"], x["name"], x["content"], "proxied" if x.get("proxied") else "dns-only",
              x["ttl"], x["id"], x.get("comment") or "-")'
}

cmd=${1:-} name=${2:-}
[ -n "$cmd" ] && [ -n "$name" ] || { sed -n '2,7p' "$0" >&2; exit 2; }
existing=$(api GET "$API?name=$name" | records)

case $cmd in
  show)
    [ -n "$existing" ] || { echo "no record for $name"; exit 0; }
    echo "$existing" | while read -r type rname addr mode ttl _ comment; do
      echo "$type $rname $addr $mode ttl $ttl comment: $comment"
    done
    ;;
  create)
    addr=${3:?give the address}
    [ -z "$existing" ] || { echo "$name already has a record; not touching it:" >&2; echo "$existing" >&2; exit 1; }
    [[ $addr =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "$addr is not an IPv4 address" >&2; exit 2; }
    type=A
    body=$(python3 -c 'import json, sys; t, n, a, ttl, tag = sys.argv[1:]
print(json.dumps({"type": t, "name": n, "content": a, "ttl": int(ttl), "proxied": False, "comment": tag}))' \
      "$type" "$name" "$addr" "$TTL" "$TAG")
    api POST "$API" "$body" | records | awk '{print "created", $1, $2, $3, $4, "ttl", $5}'
    ;;
  delete)
    [ -n "$existing" ] || { echo "no record for $name"; exit 0; }
    echo "$existing" | while read -r type rname addr _ _ id comment; do
      if [ "$comment" != "$TAG" ]; then
        echo "not deleting $type $rname $addr: it was not made by this script" >&2
        exit 1
      fi
      api DELETE "$API/$id" | records >/dev/null
      echo "deleted $type $rname $addr"
    done
    ;;
  *) sed -n '2,7p' "$0" >&2; exit 2 ;;
esac
