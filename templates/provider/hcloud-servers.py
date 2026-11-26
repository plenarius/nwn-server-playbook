#!/usr/bin/env python3
"""Short-lived Hetzner Cloud servers from a script: labelled, with an expiry, a budget and a reaper.

    hcloud-servers.py create NAME TYPE HOURS [LOCATION] [IMAGE]   make a server that expires in HOURS
    hcloud-servers.py list                                        this script's servers, time left, most cost
    hcloud-servers.py delete NAME                                 delete one of this script's servers
    hcloud-servers.py protect NAME on|off                         switch delete and rebuild protection
    hcloud-servers.py snapshot NAME [DESCRIPTION]                 save a server's disk as a snapshot
    hcloud-servers.py images                                      this script's snapshots, size, monthly cost
    hcloud-servers.py delete-image ID                             delete one of this script's snapshots
    hcloud-servers.py price TYPE LOCATION                         list price per hour, with VAT
    hcloud-servers.py reap [--dry-run]                            delete servers past their expiry

Every server and snapshot it makes carries the label managed-by=playbook (MANAGED_BY), and every server an
expires=<unix time> label. It only ever deletes, protects or reaps things that carry that label, so the
same project can hold machines it must never touch, though a project of their own is better (chapter 1).

Settings, from the environment:
  HCLOUD_TOKEN_FILE   file holding the project's API token (default ~/.config/hcloud/playbook.token, mode 600)
  SSH_KEYS            comma-separated names of SSH keys in the project to put on root (default: none)
  MAX_HOURS           the longest life create allows (default 6)
  BUDGET_EUR          the most all of this script's servers may cost together, counting each one to its
                      expiry; create refuses a server that would go over it (default 5)
  IPV6                1 to give servers an IPv6 address as well (default 1)
  EXTRA_LABELS        more labels for what create makes, e.g. "team=builds,run=42"
  MANAGED_BY          the value of the managed-by label (default playbook)
  GRACE_MIN           how many minutes past its expiry reap waits (default 5)
  ALERT_WEBHOOK_FILE  optional: file holding a Discord webhook address; reap posts what it deleted there
Python 3 alone, nothing to install. The token is read from its file and never printed.
"""
import calendar
import inspect
import json
import math
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.hetzner.cloud/v1"
TOKEN_FILE = os.path.expanduser(os.environ.get("HCLOUD_TOKEN_FILE", "~/.config/hcloud/playbook.token"))
MANAGED_BY = os.environ.get("MANAGED_BY", "playbook")
MAX_HOURS = float(os.environ.get("MAX_HOURS", "6"))
BUDGET_EUR = float(os.environ.get("BUDGET_EUR", "5"))
GRACE_MIN = float(os.environ.get("GRACE_MIN", "5"))
IPV6 = os.environ.get("IPV6", "1") == "1"


def die(msg, code=1):
    print(msg, file=sys.stderr)
    sys.exit(code)


def api(method, path, body=None):
    with open(TOKEN_FILE) as f:
        token = f.read().strip()
    req = urllib.request.Request(API + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
    except urllib.error.HTTPError as e:
        try:
            err = json.load(e)["error"]
            die(f"Hetzner said: {err['message']} ({err['code']})")
        except (ValueError, KeyError):
            die(f"Hetzner said: HTTP {e.code}")
    return json.loads(raw) if raw else {}


def selector():
    return urllib.parse.quote(f"managed-by={MANAGED_BY}")


def labels(extra=None):
    out = {"managed-by": MANAGED_BY}
    for pair in filter(None, os.environ.get("EXTRA_LABELS", "").split(",")):
        k, _, v = pair.partition("=")
        out[k.strip()] = v.strip()
    out.update(extra or {})
    return out


def ours():
    return api("GET", f"/servers?label_selector={selector()}&per_page=50")["servers"]


def find(name):
    s = api("GET", "/servers?name=" + urllib.parse.quote(name))["servers"]
    if not s:
        die(f"no server named {name}", 0)
    if s[0]["labels"].get("managed-by") != MANAGED_BY:
        die(f"not touching {name}: it has no managed-by={MANAGED_BY} label, so this script did not make it")
    return s[0]


def hourly(server_type, location):
    t = api("GET", "/server_types?name=" + urllib.parse.quote(server_type))["server_types"]
    if not t:
        die(f"no server type {server_type}")
    for p in t[0]["prices"]:
        if p["location"] == location:
            return float(p["price_hourly"]["gross"])
    die(f"{server_type} is not sold in {location}")


def created_ts(s):
    return calendar.timegm(time.strptime(s["created"][:19], "%Y-%m-%dT%H:%M:%S"))


def expiry(s):
    e = s["labels"].get("expires", "")
    return int(e) if e.isdigit() else None


def most_cost(s):
    """What a server costs if it lives to its expiry: every started hour is billed. No expiry: MAX_HOURS."""
    e = expiry(s)
    hours = (e - created_ts(s)) / 3600 if e else MAX_HOURS
    loc = s.get("location") or s["datacenter"]["location"]
    return math.ceil(max(hours, 0.01)) * hourly(s["server_type"]["name"], loc["name"])


def wait(action, what):
    for _ in range(360):
        a = api("GET", f"/actions/{action['id']}")["action"]
        if a["status"] == "success":
            return
        if a["status"] == "error":
            die(f"{what} failed: {a['error']['message']}")
        time.sleep(5)
    die(f"{what} did not finish in 30 minutes")


def cmd_create(name, server_type, hours, location="hel1", image="ubuntu-26.04"):
    hours = float(hours)
    if not 0 < hours <= MAX_HOURS:
        die(f"hours must be more than 0 and at most {MAX_HOURS:g}", 2)
    if api("GET", "/servers?name=" + urllib.parse.quote(name))["servers"]:
        die(f"a server named {name} already exists", 2)
    # The cost guard: what is already running, each to its expiry, plus this one. Hetzner bills every
    # started hour, so 0.5 hours costs as much as 1.
    price = hourly(server_type, location)
    this = math.ceil(hours) * price
    running = sum(most_cost(s) for s in ours())
    if running + this > BUDGET_EUR:
        die(f"refused: this server could cost EUR {this:.2f}, the ones running up to EUR {running:.2f}, "
            f"together over the budget of EUR {BUDGET_EUR:.2f} (BUDGET_EUR)", 3)
    # Expire two minutes short of the last paid hour, so a delete that runs a little late doesn't start one more.
    expires = int(time.time() + hours * 3600) - (120 if hours >= 1 else 0)
    body = {"name": name, "server_type": server_type, "location": location,
            "image": int(image) if image.isdigit() else image,
            "ssh_keys": [k for k in os.environ.get("SSH_KEYS", "").split(",") if k],
            "labels": labels({"expires": str(expires)}),
            "public_net": {"enable_ipv4": True, "enable_ipv6": IPV6}}
    r = api("POST", "/servers", body)
    wait(r["action"], "create")
    ip = r["server"]["public_net"]["ipv4"]["ip"]
    print(f"created {name} ({server_type}, {location}, image {image}), expires "
          f"{time.strftime('%H:%M UTC', time.gmtime(expires))}, at most EUR {this:.2f}", file=sys.stderr)
    print(ip)


def cmd_list():
    now = time.time()
    total = 0.0
    for s in ours():
        e = expiry(s)
        left = f"{(e - now) / 60:+.0f} min" if e else "no expiry"
        cost = most_cost(s)
        total += cost
        loc = (s.get("location") or s["datacenter"]["location"])["name"]
        print(s["name"], s["server_type"]["name"], loc, s["status"], s["public_net"]["ipv4"]["ip"], left,
              f"EUR {cost:.2f}", "protected" if s["protection"]["delete"] else "")
    print(f"at most EUR {total:.2f} in all; budget EUR {BUDGET_EUR:.2f}")


def cmd_delete(name):
    s = find(name)
    api("DELETE", f"/servers/{s['id']}")
    print(f"deleted {name}")


def cmd_protect(name, mode):
    if mode not in ("on", "off"):
        die("say on or off", 2)
    s = find(name)
    on = mode == "on"
    wait(api("POST", f"/servers/{s['id']}/actions/change_protection", {"delete": on, "rebuild": on})["action"],
         "change protection")
    print(f"{name}: delete and rebuild protection {mode}")


def cmd_snapshot(name, description=None):
    s = find(name)
    desc = description or f"{name} {time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime())}"
    r = api("POST", f"/servers/{s['id']}/actions/create_image",
            {"type": "snapshot", "description": desc, "labels": labels({"source": name})})
    print(f"saving {name} as snapshot {r['image']['id']} ...", file=sys.stderr)
    wait(r["action"], "snapshot")
    print(r["image"]["id"])


def cmd_images():
    per_gb = float(api("GET", "/pricing")["pricing"]["image"]["price_per_gb_month"]["gross"])
    for i in api("GET", f"/images?type=snapshot&label_selector={selector()}")["images"]:
        size = i["image_size"] or 0
        print(i["id"], i["created"][:16], f"{size:.1f} GB", f"EUR {size * per_gb:.2f}/month", i["description"])


def cmd_delete_image(image_id):
    i = api("GET", f"/images/{int(image_id)}")["image"]
    if i["labels"].get("managed-by") != MANAGED_BY:
        die(f"not touching image {image_id}: this script did not make it")
    api("DELETE", f"/images/{i['id']}")
    print(f"deleted snapshot {image_id}")


def cmd_price(server_type, location):
    print(f"EUR {hourly(server_type, location):.4f} an hour")


def cmd_reap(*flags):
    dry = "--dry-run" in flags
    now = time.time()
    gone = []
    for s in ours():
        e = expiry(s)
        if e and now < e + GRACE_MIN * 60:
            continue
        why = f"{(now - e) / 60:.0f} min past its expiry" if e else "no expiry label"
        if s["protection"]["delete"]:
            print(f"would delete {s['name']} ({why}), but it is protected; leaving it", file=sys.stderr)
            continue
        if not dry:
            api("DELETE", f"/servers/{s['id']}")
        gone.append(f"{s['name']} ({s['server_type']['name']}, {why})")
        print(("would delete " if dry else "deleted ") + gone[-1])
    if gone and not dry and os.environ.get("ALERT_WEBHOOK_FILE"):
        with open(os.environ["ALERT_WEBHOOK_FILE"]) as f:
            url = f.read().strip()
        msg = "Reaper deleted forgotten servers: " + "; ".join(gone)
        req = urllib.request.Request(url, data=json.dumps({"content": msg}).encode(),
                                     headers={"Content-Type": "application/json", "User-Agent": "hcloud-reaper/1"})
        try:
            urllib.request.urlopen(req, timeout=15)
        except (urllib.error.URLError, OSError) as e:
            print(f"could not post the alert: {e}", file=sys.stderr)
    if not gone:
        print("nothing to reap")


COMMANDS = {"create": cmd_create, "list": cmd_list, "delete": cmd_delete, "protect": cmd_protect,
            "snapshot": cmd_snapshot, "images": cmd_images, "delete-image": cmd_delete_image,
            "price": cmd_price, "reap": cmd_reap}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        die(__doc__.split("\n\n")[1], 2)
    fn = COMMANDS[sys.argv[1]]
    try:
        inspect.signature(fn).bind(*sys.argv[2:])
    except TypeError:
        die(__doc__.split("\n\n")[1], 2)
    fn(*sys.argv[2:])
