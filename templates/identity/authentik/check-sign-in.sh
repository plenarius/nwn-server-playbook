#!/usr/bin/env bash
# Checks that each site can start a sign-in at Authentik (chapter 11, tier 3). No token needed: it asks the way a
# browser would, before anyone signs in.
#
#   check-sign-in.sh https://auth.example.org website https://www.example.org/auth/callback \
#                                             forum   'https://forum.example.org/auth/oidc?provider=authentik' ...
#
# For each application slug and the address it sends people back to, it checks two things:
#   - the discovery document answers, with the issuer Authentik should have;
#   - an authorize request is sent on to the sign-in page. Authentik answers a provider it can't use (wrong
#     redirect address, or no grant types, which is what a provider made through the API gets) by sending the
#     browser straight back with error=..., before any sign-in, and that is what this looks for.
# Prints one line per site and exits 1 if any fails.
set -uo pipefail
AUTH=${1:?the sign-in address, such as https://auth.example.org}; shift
AUTH=${AUTH%/}
fail=0
while [ $# -ge 2 ]; do
  app=$1 back=$2; shift 2
  issuer=$(curl -s -m 10 "$AUTH/application/o/$app/.well-known/openid-configuration" |
    python3 -c 'import json,sys; print(json.load(sys.stdin).get("issuer",""))' 2>/dev/null)
  if [ "$issuer" != "$AUTH/application/o/$app/" ]; then
    echo "$app: no discovery document (is there an application with the slug $app?)"; fail=1; continue
  fi
  enc=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$back")
  to=$(curl -s -m 10 -o /dev/null -w '%{redirect_url}' \
    "$AUTH/application/o/authorize/?client_id=$app&response_type=code&scope=openid&state=check&redirect_uri=$enc")
  case $to in
    "$AUTH"/if/flow/*) echo "$app: ok" ;;
    *error=*) echo "$app: refused: $(sed 's/.*error=\([^&]*\).*error_description=\([^&]*\).*/\1 (\2)/' <<<"$to" |
                python3 -c 'import sys,urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))')"
              echo "    check the provider's redirect address, and that its grant types include authorization_code"; fail=1 ;;
    *) echo "$app: unexpected answer: ${to:-no redirect}"; fail=1 ;;
  esac
done
exit $fail
