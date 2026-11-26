#!/usr/bin/env python3
"""The expiry calendar: everything on a long-lived world that runs out, and a warning before it does.

    nwn-expiry check [LIST]   read every line now, print the days left, soonest first; sends nothing.
                              Exits 1 when something is inside its warning or can't be read.
    nwn-expiry run [LIST]     the same, and tell the alert channel what changed (the timer does this)
    nwn-expiry test           send one test message to the alert channel

LIST is the calendar, one file kept in git (expiry.list.example explains every line). Default:
/etc/nwn-expiry/expiry.list. Alerts go to chapter 13's watchdog channel: the webhook, style, name and mention
come from the watchdog's own settings, /etc/nwn-watchdog/watchdog.conf. Memory between runs:
/var/lib/nwn-watchdog/expiry.json. Python 3 alone, nothing to install.

Each line warns once when it comes inside its warning, once more at 7 days, at 1 day and when it has expired.
When a date moves later (something was renewed), one message says so. A line that can't be read warns after
two runs in a row, and once when it can be read again. On the 1st of each month, one message lists what comes
next, so a quiet calendar is known to be alive.
"""
import configparser
import datetime
import fcntl
import json
import os
import re
import socket
import ssl
import sys
import time
import urllib.request

LIST = os.environ.get("NWN_EXPIRY_LIST", "/etc/nwn-expiry/expiry.list")
CONF = os.environ.get("NWN_WATCHDOG_CONF", "/etc/nwn-watchdog/watchdog.conf")
STATE = os.environ.get("NWN_EXPIRY_STATE", "/var/lib/nwn-watchdog/expiry.json")
UA = "nwn-expiry/1"
DAY = 86400
AFTER = 2  # runs in a row a line must fail to read before it warns


def day(ts):
    return datetime.datetime.fromtimestamp(ts, datetime.timezone.utc).strftime("%Y-%m-%d")


def parse_day(text):
    return datetime.datetime.strptime(text, "%Y-%m-%d").replace(tzinfo=datetime.timezone.utc).timestamp()


def get_json(url, accept="application/json"):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": accept})
    with urllib.request.urlopen(req, timeout=20) as res:
        return json.load(res)


# --- the kinds: each returns the time it runs out (seconds since 1970, UTC), or raises with a reason -------

def when_cert(what):
    """The certificate a TLS server hands out for this name, read live. what: host or host:port."""
    host, _, port = what.partition(":")
    try:
        with socket.create_connection((host, int(port or 443)), timeout=15) as raw:
            with ssl.create_default_context().wrap_socket(raw, server_hostname=host) as tls:
                return ssl.cert_time_to_seconds(tls.getpeercert()["notAfter"])
    except ssl.SSLCertVerificationError as e:
        raise ValueError(f"certificate not accepted: {e.verify_message}")
    except socket.gaierror:
        raise ValueError(f"cannot find the name {host}")
    except OSError as e:
        raise ValueError(f"no TLS answer from {host} port {port or 443} ({e.strerror or e})")


_rdap = {}


def when_domain(what):
    """The domain's registration expiry, from its registry over RDAP (the successor of whois)."""
    name = what.lower().rstrip(".")
    if not _rdap:
        for tlds, urls in get_json("https://data.iana.org/rdap/dns.json")["services"]:
            for tld in tlds:
                _rdap[tld] = urls[0]
    labels = name.split(".")
    base = next((_rdap[".".join(labels[i:])] for i in range(1, len(labels)) if ".".join(labels[i:]) in _rdap), None)
    if not base:
        raise ValueError("its registry has no RDAP service: write the date from your registrar as a date line")
    data = get_json(base.rstrip("/") + "/domain/" + name, "application/rdap+json")
    for event in data.get("events", []):
        if event.get("eventAction") == "expiration":
            return datetime.datetime.fromisoformat(event["eventDate"].replace("Z", "+00:00")).timestamp()
    raise ValueError("its registry doesn't publish the expiry: write the date from your registrar as a date line")


def when_eol(what):
    """The end of support for a version of something, from endoflife.date. what: product/version."""
    product, _, version = what.partition("/")
    data = get_json(f"https://endoflife.date/api/v1/products/{product}/releases/{version}")["result"]
    if not data.get("eolFrom"):
        raise ValueError(f"endoflife.date has no end date for {product} {version} yet")
    return parse_day(data["eolFrom"])


def when_date(what):
    """A date written by hand: a token's expiry, a contract, a card."""
    return parse_day(what)


def when_every(what):
    """Something done by hand on a rhythm: YYYY-MM-DD+NNd, the day it was last done and how often."""
    m = re.fullmatch(r"(\d{4}-\d\d-\d\d)\+(\d+)d", what)
    if not m:
        raise ValueError("write it as YYYY-MM-DD+NNd: the day it was last done, and every how many days")
    return parse_day(m[1]) + int(m[2]) * DAY


KINDS = {"cert": when_cert, "domain": when_domain, "eol": when_eol, "date": when_date, "every": when_every}


def read_list(path):
    """Lines of NAME KIND WHAT WARN NOTE...; a line starting with # is a comment. A mistake stops everything."""
    items, errors = [], []
    with open(path) as f:
        for n, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            f_ = line.split(None, 4)
            if len(f_) < 4 or f_[1] not in KINDS or not f_[3].isdigit():
                errors.append(f"{path} line {n}: want NAME KIND WHAT WARN [NOTE], KIND one of {', '.join(KINDS)}")
                continue
            if any(i["name"] == f_[0] for i in items):
                errors.append(f"{path} line {n}: the name {f_[0]} is used twice")
            items.append({"name": f_[0], "kind": f_[1], "what": f_[2], "warn": int(f_[3]),
                          "note": f_[4] if len(f_) > 4 else ""})
    if errors:
        raise SystemExit("\n".join(errors))
    return items


def read_all(items, now):
    """Each item with its expiry or its problem, soonest first; problems at the top."""
    for i in items:
        try:
            i["at"], i["problem"] = KINDS[i["kind"]](i["what"]), None
            i["left"] = (i["at"] - now) / DAY
        except Exception as e:  # a line that breaks is a line that warns, never a quiet calendar
            i["at"], i["left"], i["problem"] = None, None, str(getattr(e, "reason", e))
    return sorted(items, key=lambda i: (i["problem"] is None, i["left"] if i["left"] is not None else 0))


def stages(warn):
    """The days at which a line warns: its own warning, then 7, 1 and 0 (expired), as far as they fall inside."""
    return sorted({warn, 7, 1, 0} & set(range(warn + 1)), reverse=True)


def level(i):
    """How many of a line's stages it has reached."""
    return sum(1 for s in stages(i["warn"]) if i["left"] <= s)


def left_text(left):
    if left < 0:
        d = int(-left)
        return "expired today" if d == 0 else f"expired {d} day{'s' if d != 1 else ''} ago"
    if left < 2:
        return f"{left * 24:.0f} hours left"
    return f"{int(left)} days left"


def describe(i):
    return f"{i['name']}: {left_text(i['left'])}, on {day(i['at'])}" + (f" · {i['note']}" if i["note"] else "")


# --- the alert channel: the same settings and the same sending as nwn-watchdog -------------------------------

def channel():
    cfg = configparser.ConfigParser(inline_comment_prefixes=("#",))
    if not cfg.read(CONF) or "watchdog" not in cfg:
        raise SystemExit(f"cannot read {CONF}, or it has no [watchdog] section (chapter 13)")
    return cfg["watchdog"]


def send(s, text):
    style = s.get("style", "discord")
    with open(s.get("webhook_file", "/etc/nwn-watchdog/webhook")) as f:
        url = f.read().strip()
    if style == "discord":
        role = s.get("mention_role", "").strip()
        if role and "ALERT" in text:
            text = f"<@&{role}> " + text
        body = {"content": text[:2000], "allowed_mentions": {"roles": [role]} if role else {"parse": []}}
        data, kind = json.dumps(body).encode(), "application/json"
    elif style == "slack":
        data, kind = json.dumps({"text": text.replace("**", "*")}).encode(), "application/json"
    elif style == "plain":
        data, kind = text.replace("**", "").encode(), "text/plain; charset=utf-8"
    else:
        raise SystemExit(f"unknown style '{style}' in {CONF}: use discord, slack or plain")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": kind, "User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=15) as res:
            return 200 <= res.status < 300
    except Exception as e:
        print(f"could not send the message: {getattr(e, 'code', '')} {getattr(e, 'reason', e)}", file=sys.stderr)
        return False


# --- memory between runs ----------------------------------------------------------------------------------

def load():
    try:
        with open(STATE) as f:
            return json.load(f)
    except FileNotFoundError:
        return {"items": {}}


def save(state):
    tmp = STATE + ".new"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=1)
    os.replace(tmp, STATE)


def run(items, state, now):
    s = channel()
    title = s.get("name", "nwn-watchdog") + ": expiry calendar"
    known = state.setdefault("items", {})
    for gone in [n for n in known if n not in {i["name"] for i in items}]:
        del known[gone]  # a line taken out of the list is forgotten quietly
    lines, after_send = [], []
    for i in read_all(items, now):
        st = known.setdefault(i["name"], {"level": 0, "fails": 0})
        if i["problem"]:
            st["fails"] += 1
            if st["fails"] >= AFTER and not st.get("fail_alerted"):
                lines.append(f"ALERT {i['name']}: can't read it: {i['problem']}")
                after_send.append(lambda st=st: st.update(fail_alerted=True))
            continue
        if st.get("fail_alerted"):
            lines.append(f"OK {i['name']}: readable again, {left_text(i['left'])}")
            after_send.append(lambda st=st: st.update(fail_alerted=False))
        st["fails"] = 0
        was = st.get("at")
        if was and i["at"] > was + 60 and st["level"] > 0:  # moved later: renewed
            lines.append(f"OK {i['name']}: renewed, now runs to {day(i['at'])} ({left_text(i['left'])})")
        if was is None or abs(i["at"] - was) > 60:
            st["level"] = 0  # a new date starts its stages again
        st["at"] = i["at"]
        reached = level(i)
        if reached > st["level"]:
            word = "EXPIRED" if i["left"] < 0 else "expires soon"
            lines.append(f"ALERT {word} {describe(i)}")
            after_send.append(lambda st=st, r=reached: st.update(level=r))
    monthly = time.strftime("%Y-%m", time.gmtime(now)) != state.get("summary_month")
    if monthly:
        soon = [i for i in sorted(items, key=lambda i: i["left"] if i["left"] is not None else -1e9)][:5]
        listed = "; ".join(f"{i['name']} {day(i['at'])}" if i["at"] else f"{i['name']} unreadable" for i in soon)
        lines.append(f"{len(items)} lines in the calendar. Next: {listed}")
    sent = bool(lines) and send(s, f"**{title}**\n" + "\n".join(lines))
    if sent:
        for f in after_send:
            f()
        if monthly:
            state["summary_month"] = time.strftime("%Y-%m", time.gmtime(now))
    for line in lines:
        print(line if sent else f"not sent, will try again: {line}")
    print(f"{len(items)} lines, {sum(1 for i in items if i['problem'] or level(i))} inside their warning or unreadable")


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    path = sys.argv[2] if len(sys.argv) > 2 else LIST
    now = time.time()
    if cmd == "check":
        bad = 0
        for i in read_all(read_list(path), now):
            if i["problem"]:
                bad += 1
                print(f"FAIL     {i['name']} ({i['kind']} {i['what']}): {i['problem']}")
                continue
            hit = level(i) > 0
            bad += hit
            print(f"{'WARN' if hit else 'ok  '} {i['left']:6.1f}  {day(i['at'])}  {i['name']} ({i['kind']} {i['what']}, warns at {i['warn']})")
        raise SystemExit(1 if bad else 0)
    if cmd == "test":
        if not send(channel(), f"**{channel().get('name', 'nwn-watchdog')}: expiry calendar**\ntest message from {socket.gethostname()}: expiry warnings arrive here"):
            raise SystemExit(1)
        print("sent")
        return
    if cmd != "run":
        raise SystemExit(__doc__)
    items = read_list(path)
    lock = open(STATE + ".lock", "a")
    fcntl.flock(lock, fcntl.LOCK_EX)
    state = load()
    run(items, state, now)
    save(state)


if __name__ == "__main__":
    main()
