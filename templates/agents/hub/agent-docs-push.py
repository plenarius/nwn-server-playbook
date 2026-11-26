#!/usr/bin/env python3
"""agent-docs-push: write each worker's agent guide from one source on the hub, and push it there.

    agent-docs-push --dry-run [MACHINE ...]   build the guides into OUT only, to read first
    agent-docs-push [MACHINE ...]             build and push (default: every machine in MACHINES)

For each machine it sends probe.sh there over SSH (run as the agent user) to see what is really installed,
then joins, in order:
  1. common.md, the guide every worker gets, with {machine}, {date}, {capline} and {tmpline} filled in;
  2. <machine>.md, that machine's own notes;
  3. a table of the tools found there, and the data folders that exist;
  4. the sections of the hub's rules file named in SECTIONS, cut out by their "## " headings. A missing
     heading stops it, so a renamed section can't silently drop a rule from every guide.
It writes the result to each path in GUIDE_FILES under the agent user's home (one per agent tool you use:
Claude Code reads ~/.claude/CLAUDE.md, many others read AGENTS.md).

Settings: ~/.config/agent-docs/agent-docs.env (AGENT_DOCS_SETTINGS= to use another), KEY=value lines; see
agent-docs.env.example. Python 3 alone. Chapter 15, tier 3.
"""
import datetime
import os
import pathlib
import re
import shlex
import subprocess
import sys


def read_env(path):
    """KEY=value lines: quotes removed, $VARS and a leading ~/ expanded (~agent stays for the worker's shell)."""
    env = {}
    for line in pathlib.Path(path).read_text().splitlines():
        m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line)
        if not m or line.lstrip().startswith("#"):
            continue
        val = m.group(2).strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
            val = val[1:-1]
        elif " #" in val:
            val = val.split(" #", 1)[0].rstrip()
        val = os.path.expandvars(val)
        env[m.group(1)] = os.path.expanduser(val) if val.startswith("~/") else val
    return env


SETTINGS = os.environ.get("AGENT_DOCS_SETTINGS") or os.path.expanduser("~/.config/agent-docs/agent-docs.env")
S = read_env(SETTINGS)
TEMPLATES = pathlib.Path(S.get("TEMPLATES", os.path.dirname(SETTINGS)))
OUT = pathlib.Path(S.get("OUT", os.path.expanduser("~/.cache/agent-docs")))
RULES = pathlib.Path(S["RULES"])
SECTIONS = [s for s in S.get("SECTIONS", "").split("|") if s]
GUIDE_FILES = S.get("GUIDE_FILES", ".claude/CLAUDE.md").split()


def machine(key):
    k = key.upper().replace("-", "_")
    return {"key": key, "name": S.get(k + "_NAME", key), "ssh": shlex.split(S[k + "_SSH"]),
            "as": S.get(k + "_AS", "sudo -u agent"), "home": S.get(k + "_HOME", "~agent")}


def sections():
    if not SECTIONS:
        return ""
    parts = re.split(r"(?m)^(?=## )", RULES.read_text())
    keep = [p.rstrip() + "\n" for p in parts
            if (m := re.match(r"## (.+)", p)) and any(m.group(1).strip() == s for s in SECTIONS)]
    found = {re.match(r"## (.+)", p).group(1).strip() for p in keep}
    missing = [s for s in SECTIONS if s not in found]
    if missing:
        sys.exit(f"sections not found in {RULES}: {missing}")
    return "\n".join(keep)


def probe(m):
    head = "".join(f"{k}={shlex.quote(S.get(k, ''))}\n" for k in ("PROBE_TOOLS", "PROBE_DATA"))
    r = subprocess.run(m["ssh"] + [m["as"] + " bash -s"], input=head + (TEMPLATES / "probe.sh").read_text(),
                       text=True, capture_output=True, timeout=180)
    if r.returncode:
        sys.exit(f"probe failed on {m['name']}: {r.stderr.strip()}")
    return [line.split("\t") for line in r.stdout.splitlines() if "\t" in line]


def size(v):
    return f"{int(v) / 2**30:.1f} GB" if v.isdigit() else None


def build(m, rules):
    rows = probe(m)
    get = lambda kind: [r for r in rows if r[0] == kind]
    cap = dict(r[1].split("=", 1) for r in get("cap") if "=" in r[1])
    cpu = re.match(r"(\d+(?:\.\d+)?)s", cap.get("CPUQuotaPerSecUSec", ""))
    capd = ", ".join(x for x in [size(cap.get("MemoryMax", "")), f"{float(cpu.group(1)):g} cores" if cpu else None] if x)
    tmp = next((r[1] for r in get("tmp")), "")
    capline = (f"Everything your account runs shares a fence of {capd}. Past it, the kernel stops your biggest process."
               if capd else "Nothing fences your account here: a runaway job slows every agent on this machine.")
    tmpline = ("`/tmp` here is memory (a tmpfs): what you leave there uses RAM until a cleaner removes it, an hour or two after your session ends. Big files go under `~/work`."
               if tmp == "tmpfs" else "`/tmp` here is on disk.")
    doc = (TEMPLATES / "common.md").read_text().format(machine=m["name"], date=datetime.date.today().isoformat(),
                                                       capline=capline, tmpline=tmpline)
    own = TEMPLATES / f"{m['key']}.md"
    if own.exists():
        doc += "\n" + own.read_text()
    doc = re.sub(r"<!--.*?-->\n?", "", doc, flags=re.S)  # notes for you in the templates stay on the hub
    doc += "\n## Tools on this machine (checked when this guide was written)\n\n| Command | Version |\n|---|---|\n"
    doc += "".join(f"| `{r[1]}` | {r[2]} |\n" for r in get("tool"))
    if get("missing"):
        doc += "\n**Not here:** " + ", ".join(f"`{r[1]}`" for r in get("missing")) + ".\n"
    hw = next(iter(get("hw")), None)
    if hw:
        doc += f"\nThe machine has {hw[1]} cores and {hw[2]} GB of memory in all.\n"
    data = get("data")
    doc += "\n## Data on this machine\n\n" + ("".join(f"- `{r[1]}`\n" for r in data) if data else "- None.\n")
    if rules:
        doc += "\n# Rules from the hub\n\n" + rules
    return doc


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    dry = "--dry-run" in sys.argv
    rules = sections()
    OUT.mkdir(parents=True, exist_ok=True)
    for key in args or S["MACHINES"].split():
        m = machine(key)
        doc = build(m, rules)
        (OUT / f"{key}.md").write_text(doc)
        words = len(doc.split())
        if dry:
            print(f"{key}: {words} words -> {OUT / (key + '.md')}")
            continue
        for path in GUIDE_FILES:
            full = f"{m['home']}/{path}"
            remote = f"mkdir -p {os.path.dirname(full)} && cat > {full}"
            subprocess.run(m["ssh"] + [m["as"] + " sh -c " + shlex.quote(remote)], input=doc, text=True,
                           check=True, timeout=60)
        print(f"{key}: pushed {words} words to {', '.join(GUIDE_FILES)}")


if __name__ == "__main__":
    main()
