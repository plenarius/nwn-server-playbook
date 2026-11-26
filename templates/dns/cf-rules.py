#!/usr/bin/env python3
"""Cloudflare firewall and redirect rules kept in a file in git, applied through the API.

    cf-rules.py export DIR       save the zone's rules for every phase this script knows into DIR, as they are now
    cf-rules.py plan FILE        show what apply would add, change or remove; changes nothing
    cf-rules.py apply FILE       make the zone's rules match FILE
    cf-rules.py remove FILE      delete every rule FILE owns

FILE (cf-rules.example.json shows one) names an owner and lists rules per phase. Every rule has a "ref" that
starts with the owner and a dash, such as "playbook-www-redirect". This script only ever adds, changes or
deletes rules whose ref starts that way, so rules made in the dashboard, or by anyone else, are left exactly as
they are and where they are. New rules go at the end of their phase.

Needs, in the environment: CF_API_TOKEN, a token for this one zone with the permissions for the phases you use
(Zone WAF for firewall rules, Dynamic URL Redirects for redirects; reading is enough for export and plan), and
CF_ZONE_ID. The token is never printed. Python 3 alone, nothing to install.
"""
import json
import os
import sys
import urllib.error
import urllib.request

PHASES = ("http_request_firewall_custom", "http_request_dynamic_redirect", "http_ratelimit")
FIELDS = ("description", "expression", "action", "action_parameters", "ratelimit", "enabled")


def die(msg, code=1):
    print(msg, file=sys.stderr)
    sys.exit(code)


def api(method, path, body=None, missing_ok=False):
    try:
        token, zone = os.environ["CF_API_TOKEN"], os.environ["CF_ZONE_ID"]
    except KeyError as e:
        die(f"set {e.args[0]}", 2)
    req = urllib.request.Request(f"https://api.cloudflare.com/client/v4/zones/{zone}{path}", method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)["result"]
    except urllib.error.HTTPError as e:
        if missing_ok and e.code == 404:
            return None
        try:
            errs = json.load(e).get("errors", [])
            die("Cloudflare said: " + "; ".join(x.get("message", "?") for x in errs))
        except ValueError:
            die(f"Cloudflare said: HTTP {e.code}")


def entrypoint(phase):
    return api("GET", f"/rulesets/phases/{phase}/entrypoint", missing_ok=True)


def load(path):
    with open(path) as f:
        spec = json.load(f)
    owner = spec.get("owner") or die(f"{path} has no owner")
    for phase, rules in spec["phases"].items():
        if phase not in PHASES:
            die(f"{path}: unknown phase {phase}")
        refs = [r.get("ref", "") for r in rules]
        for ref in refs:
            if not ref.startswith(owner + "-"):
                die(f"{path}: rule ref {ref!r} must start with {owner}-")
        if len(set(refs)) != len(refs):
            die(f"{path}: two rules in {phase} share a ref")
    return owner, spec["phases"]


def want(rule):
    r = {k: rule[k] for k in FIELDS if k in rule}
    r.setdefault("enabled", True)
    return r


def same(live, rule):
    return all(live.get(k) == v for k, v in want(rule).items())


def diff(owner, phases):
    """Yields (phase, ruleset or None, what, ref, live rule or None, wanted rule or None)."""
    for phase, rules in phases.items():
        rs = entrypoint(phase)
        live = {r["ref"]: r for r in (rs or {}).get("rules", []) if r.get("ref", "").startswith(owner + "-")}
        wanted = {r["ref"]: r for r in rules}
        for ref, r in live.items():
            if ref not in wanted:
                yield phase, rs, "remove", ref, r, None
        for ref, r in wanted.items():
            if ref not in live:
                yield phase, rs, "add", ref, None, r
            elif not same(live[ref], r):
                yield phase, rs, "change", ref, live[ref], r
            else:
                yield phase, rs, "keep", ref, live[ref], r


def cmd_export(folder):
    os.makedirs(folder, exist_ok=True)
    for phase in PHASES:
        rs = entrypoint(phase)
        with open(os.path.join(folder, phase + ".json"), "w") as f:
            json.dump(rs or {"rules": []}, f, indent=2, sort_keys=True)
        print(f"{phase}: {len((rs or {}).get('rules', []))} rules saved")


def cmd_plan(path):
    owner, phases = load(path)
    for phase, _, what, ref, _, _ in diff(owner, phases):
        print(f"{what:6} {phase} {ref}")


def cmd_apply(path):
    owner, phases = load(path)
    steps = list(diff(owner, phases))
    # Removals first, so a zone at its rule limit has room for the new ones.
    steps.sort(key=lambda s: {"remove": 0, "change": 1, "add": 2, "keep": 3}[s[2]])
    created = {}
    for phase, rs, what, ref, live, rule in steps:
        if what == "keep":
            print(f"same    {phase} {ref}")
        elif what == "remove":
            api("DELETE", f"/rulesets/{rs['id']}/rules/{live['id']}")
            print(f"removed {phase} {ref}")
        elif what == "change":
            api("PATCH", f"/rulesets/{rs['id']}/rules/{live['id']}", dict(want(rule), ref=ref))
            print(f"changed {phase} {ref}")
        elif rs or phase in created:
            api("POST", f"/rulesets/{(rs or created[phase])['id']}/rules", dict(want(rule), ref=ref))
            print(f"added   {phase} {ref}")
        else:
            # The zone has no rules in this phase yet: make its entry point with this one rule.
            created[phase] = api("PUT", f"/rulesets/phases/{phase}/entrypoint", {"rules": [dict(want(rule), ref=ref)]})
            print(f"added   {phase} {ref} (first rule in this phase)")


def cmd_remove(path):
    owner, phases = load(path)
    for phase in phases:
        rs = entrypoint(phase)
        for r in (rs or {}).get("rules", []):
            if r.get("ref", "").startswith(owner + "-"):
                api("DELETE", f"/rulesets/{rs['id']}/rules/{r['id']}")
                print(f"removed {phase} {r['ref']}")


COMMANDS = {"export": cmd_export, "plan": cmd_plan, "apply": cmd_apply, "remove": cmd_remove}

if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in COMMANDS:
        die(__doc__.split("\n\n")[1], 2)
    COMMANDS[sys.argv[1]](sys.argv[2])
