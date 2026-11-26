#!/usr/bin/env python3
"""A small outside watchdog for an NWN server. It runs on a machine that is not the game host.

    nwn-watchdog run            check everything once, and send what changed (the timer does this)
    nwn-watchdog status         show each check's result now, and what is failing; sends nothing
    nwn-watchdog test           send one test message to the alert channel
    nwn-watchdog pause MINUTES  stay quiet for planned work; it lifts itself
    nwn-watchdog resume         stop a pause now

Settings: /etc/nwn-watchdog/watchdog.conf (watchdog.conf.example explains every line).
Memory between runs: /var/lib/nwn-watchdog/state.json. Python 3 alone, nothing to install.

An alert goes out once, after a check has failed `after` runs in a row, and one message says when it passes
again. While it stays down, nothing more is sent. If the alert channel can't be reached, nothing is marked as
sent, so the next run tries again.
"""
import configparser
import datetime
import fcntl
import json
import os
import socket
import ssl
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

CONF = os.environ.get("NWN_WATCHDOG_CONF", "/etc/nwn-watchdog/watchdog.conf")
STATE = os.environ.get("NWN_WATCHDOG_STATE", "/var/lib/nwn-watchdog/state.json")
UA = "nwn-watchdog/1"
WEEK = 7 * 24 * 3600


def when(ts):
    return datetime.datetime.fromtimestamp(ts, datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")


def took(seconds):
    m = int(seconds // 60)
    return f"{m} min" if m < 120 else f"{m // 60} h {m % 60} min"


# --- the checks: each returns a list of (name, problem); problem is None when it passes ---------------------

def check_game(name, c, s):
    """Ask the game server the question a player's game asks (BNXI), up to three times."""
    host, port = c["host"], c.getint("port", 5121)
    for _ in range(3):
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
                sock.settimeout(3)
                sock.sendto(b"BNXI" + struct.pack("<H", port), (host, port))
                reply, _ = sock.recvfrom(2048)
            if reply[:4] == b"BNXR":
                return [(name, None)]
            return [(name, f"{host} port {port} answered, but not like a game server")]
        except socket.gaierror:
            return [(name, f"cannot find the name {host}")]
        except OSError:
            pass
    return [(name, f"no answer from {host} port {port}")]


def check_https(name, c, s):
    """The page answers 200 (and contains `expect`, if set); and its certificate has cert_days left."""
    url, expect = c["url"], c.get("expect", "")
    results = []
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=10) as res:
            body = res.read(1_000_000).decode("utf-8", "replace")
        results.append((name, f"answered, but without the text '{expect}'" if expect and expect not in body else None))
    except urllib.error.HTTPError as e:
        results.append((name, f"answered {e.code}"))
    except Exception as e:  # timeouts, refused connections, bad certificates
        results.append((name, f"no answer ({getattr(e, 'reason', e)})"))

    u = urllib.parse.urlsplit(url)
    days_wanted = s.getint("cert_days", 14)
    try:
        with socket.create_connection((u.hostname, u.port or 443), timeout=10) as raw:
            with ssl.create_default_context().wrap_socket(raw, server_hostname=u.hostname) as tls:
                not_after = ssl.cert_time_to_seconds(tls.getpeercert()["notAfter"])
        days = (not_after - time.time()) / 86400
        problem = f"expires in {days:.1f} days, on {when(not_after)}" if days < days_wanted else None
    except ssl.SSLCertVerificationError as e:
        problem = f"not accepted: {e.verify_message}"
    except OSError:
        return results  # the site itself is down, and that alert says so; the certificate stays as it was
    results.append((f"{name} certificate", problem))
    return results


def check_report(name, c, s):
    """Ask the game host, over SSH, for its disk use and its newest backups (watchdog-report.sh answers)."""
    try:
        out = subprocess.run(["ssh", "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", c["ssh"]],
                             capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired:
        return [(name, "no report: SSH timed out")]
    if out.returncode != 0:
        return [(name, f"no report: SSH said {(out.stderr.strip().splitlines() or ['nothing'])[-1][:150]}")]
    results = [(name, None)]
    limit = s.getint("disk_percent", 90)
    for line in out.stdout.splitlines():
        f = line.split()
        if len(f) == 3 and f[0] == "disk":
            used = int(f[1])
            results.append((f"{name} disk {f[2]}", f"{used}% full" if used >= limit else None))
        elif len(f) == 2 and f[0] in STAMPS:
            label, setting, default = STAMPS[f[0]]
            results.append((f"{name} {label}", stamp_problem(f[1], s.getfloat(setting, default))))
    return results


# The report's lines that carry a time (YYYYmmdd-HHMMSS, UTC), what the alerts call them, and how old they may get.
STAMPS = {
    "backup": ("backup", "backup_hours", 26),       # tier 1's nightly backup
    "borg": ("borg backup", "borg_hours", 26),      # chapter 12, tier 2: the last good borg backup
    "vault": ("vault history", "vault_hours", 2),   # chapter 12, tier 3: the vault history's last good run
}


def stamp_problem(stamp, hours):
    if stamp == "none":
        return "none made yet"
    made = datetime.datetime.strptime(stamp, "%Y%m%d-%H%M%S").replace(tzinfo=datetime.timezone.utc).timestamp()
    age = (time.time() - made) / 3600
    if age <= hours:
        return None
    return f"the newest is {f'{age:.0f} hours' if age >= 2 else f'{age * 60:.0f} minutes'} old, from {when(made)}"


def check_stamp(name, c, s):
    """A time written in a file on this machine, such as the control host's own last borg backup."""
    try:
        with open(c["file"]) as f:
            stamp = f.read().strip() or "none"
    except FileNotFoundError:
        stamp = "none"
    return [(name, stamp_problem(stamp, c.getfloat("hours", 26)))]


CHECKS = {"game": check_game, "https": check_https, "report": check_report, "stamp": check_stamp}


def run_checks(cfg):
    s = cfg["watchdog"]
    results = []
    for name in cfg.sections():
        if name == "watchdog":
            continue
        c = cfg[name]
        try:
            results += CHECKS[c["check"]](name, c, s)
        except Exception as e:  # a check that breaks is a failing check, not a silent watchdog
            results.append((name, f"the check itself failed: {e}"))
    return results


# --- the alert channel ------------------------------------------------------------------------------------

def send(cfg, text):
    s = cfg["watchdog"]
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
        data, kind = json.dumps({"text": text.replace("**", "*")}).encode(), "application/json"  # Slack's bold
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
        return {"checks": {}}


def save(state):
    tmp = STATE + ".new"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=1)
    os.replace(tmp, STATE)


def configured(cfg, name):
    """Whether a remembered result still belongs to a check in the settings ("website certificate" to [website])."""
    return any(name == s or name.startswith(s + " ") for s in cfg.sections() if s != "watchdog")


def run(cfg, state, now):
    s = cfg["watchdog"]
    title, after = s.get("name", "nwn-watchdog"), s.getint("after", 2)
    if state.get("paused_until", 0) > now:
        print(f"paused until {when(state['paused_until'])}")
        return
    state.pop("paused_until", None)
    results = run_checks(cfg)
    checks = state.setdefault("checks", {})
    # A check taken out of the settings is forgotten quietly.
    for gone in [n for n in checks if not configured(cfg, n)]:
        del checks[gone]
    down, up = [], []
    for name, problem in results:
        st = checks.get(name)
        if problem:
            st = checks.setdefault(name, {"fails": 0, "since": now, "alerted": False})
            st["fails"] += 1
            st["reason"] = problem
            if st["fails"] >= after and not st["alerted"]:
                down.append(name)
        elif st:
            if st["alerted"]:
                up.append(name)
            else:
                del checks[name]  # failed once or twice, then passed: nobody needs to hear about it
    lines = [f"ALERT {n}: {checks[n]['reason']} (failing since {when(checks[n]['since'])})" for n in down]
    lines += [f"OK {n}: passing again, after {took(now - checks[n]['since'])}" for n in up]
    weekly = now - state.get("summary_at", 0) >= WEEK
    if weekly:
        failing = [n for n, p in results if p]
        news = "started watching" if "summary_at" not in state else "still watching"
        lines.append(f"{news} {len(results)} check{'s' if len(results) != 1 else ''}: " + (f"{len(failing)} failing ({', '.join(failing)})" if failing else "all passing"))
    sent = bool(lines) and send(cfg, f"**{title}**\n" + "\n".join(lines))
    if sent:
        for n in down:
            checks[n]["alerted"] = True
        for n in up:
            del checks[n]
        if weekly:
            state["summary_at"] = now
    for line in lines:
        print(line if sent else f"not sent, will try again: {line}")
    print(f"{len(results)} checks, {sum(1 for _, p in results if p)} failing")


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    cfg = configparser.ConfigParser(inline_comment_prefixes=("#",))
    if not cfg.read(CONF) or "watchdog" not in cfg:
        raise SystemExit(f"cannot read {CONF}, or it has no [watchdog] section")
    # One at a time: a pause typed while a run is under way must not be overwritten when that run saves.
    if cmd in ("run", "pause", "resume"):
        lock = open(STATE + ".lock", "a")
        fcntl.flock(lock, fcntl.LOCK_EX)
    state, now = load(), time.time()
    if cmd == "run":
        run(cfg, state, now)
    elif cmd == "status":
        for name, problem in run_checks(cfg):
            print(f"{'FAIL' if problem else 'ok  '} {name}{': ' + problem if problem else ''}")
        for name, st in state.get("checks", {}).items():
            if not configured(cfg, name):
                continue
            print(f"remembered: {name} failing since {when(st['since'])}, {st['fails']} runs, alert {'sent' if st['alerted'] else 'not sent yet'}")
        if state.get("paused_until", 0) > now:
            print(f"paused until {when(state['paused_until'])}")
        return
    elif cmd == "test":
        if not send(cfg, f"**{cfg['watchdog'].get('name', 'nwn-watchdog')}**\ntest message from {socket.gethostname()}: alerts arrive here"):
            raise SystemExit(1)
        print("sent")
        return
    elif cmd == "pause" and len(sys.argv) == 3 and sys.argv[2].isdigit():
        state["paused_until"] = now + 60 * int(sys.argv[2])
        print(f"paused until {when(state['paused_until'])}")
    elif cmd == "resume":
        state.pop("paused_until", None)
        print("resumed")
    else:
        raise SystemExit(__doc__)
    save(state)


if __name__ == "__main__":
    main()
