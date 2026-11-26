#!/usr/bin/env python3
"""Check that the server has switched on every NWNX plugin the module's scripts use.

    check_plugins.py SOURCE_FOLDER SWITCHES_FILE
    ssh nwn@SERVER 'grep -E "^NWNX_[A-Z0-9_]+_SKIP=" game/.env' | check_plugins.py SOURCE_FOLDER -

SWITCHES_FILE holds the server's plugin lines, such as NWNX_SQL_SKIP=n. The second form reads them from the
server over ssh; that command sends only the switch lines, never a password.

Each NWNX script file (nwnx_*.nss) names its plugin in a line like
    const string NWNX_SQL = "NWNX_SQL";
This looks at every nwnx_*.nss that some script in the module includes, reads that name, and checks that the
server has the matching NWNX_<NAME>_SKIP=n. It lists what is missing and exits 1, or says all is well and exits 0.
A module that uses a plugin the server has not switched on loads without complaint and then fails at the moment
a player uses that feature.
"""
import glob
import os
import re
import sys

INCLUDE = re.compile(r'^\s*#include\s+"(nwnx_[a-z0-9_]+)"', re.M)
PLUGIN = re.compile(r'^\s*const\s+string\s+NWNX_\w+\s*=\s*"(NWNX_\w+)"', re.M)
SWITCH = re.compile(r'^(NWNX_[A-Z0-9_]+)_SKIP=(\S*)', re.M)


def main(source, switches):
    files = {os.path.basename(p)[:-4].lower(): p
             for p in glob.glob(os.path.join(source, '**', '*.nss'), recursive=True)}
    used = set()
    for path in files.values():
        with open(path, encoding='latin-1') as f:
            used.update(INCLUDE.findall(f.read()))
    text = sys.stdin.read() if switches == '-' else open(switches).read()
    on = {name for name, value in SWITCH.findall(text) if value.lower() in ('n', 'no', 'false', '0')}
    missing, unknown, needed = [], [], set()
    for include in sorted(used):
        if include not in files:
            missing.append(f'{include}.nss is included by a script but is not in {source}')
            continue
        with open(files[include], encoding='latin-1') as f:
            found = PLUGIN.search(f.read())
        if not found:
            unknown.append(include)
            continue
        plugin = found.group(1)
        needed.add(plugin)
        if plugin.upper() not in on:
            missing.append(f'{plugin}: the module includes {include}.nss, '
                           f'but the server has no line {plugin.upper()}_SKIP=n')
    for include in unknown:
        print(f'note: could not tell which plugin {include}.nss belongs to; check it by hand')
    if missing:
        print(f'{len(missing)} problem(s):')
        for line in missing:
            print('  ' + line)
        return 1
    print(f'the server has every plugin the module uses switched on ({len(needed)} checked)')
    return 0


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2]))
