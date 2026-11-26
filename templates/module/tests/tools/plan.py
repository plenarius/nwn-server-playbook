#!/usr/bin/env python3
"""Decides which tests a change can affect, and splits them into lanes (chapter 6, tier 3).

    plan.py                          every test, in one lane
    plan.py --base main              only the tests the changes since main can affect
    plan.py --base main --lanes 3    the same, split into up to three lanes
    plan.py ... --github-output F    also writes mode, count and lanes (a matrix) for a workflow

What it prints: the mode and why, then one line per lane with the tests in it. The modes:

    full    every test: no base was given, or the change touches the test harness, the build or the module's
            own settings (module.ifo: its haks, its events), where anything could break
    select  only the tests the change can reach (below)
    boot    the module changed but no test reaches the change: build it and start it, run no tests, so a script
            that breaks the module's start still fails
    none    nothing the test module is made of changed (documents, migrations, other folders): no server at all

How a test "reaches" a file, all read from the files themselves, nothing to keep up to date by hand:

    - the test's own script, and every script it includes, and theirs (#include "x");
    - any name in quotes in those scripts: ExecuteScript("x"), CreateObject(..., "x", ...), a table in an SQL
      string, a tag. A changed file whose name (before the first dot) is one of those words is reached;
    - through the module: a script that includes a changed script is changed too, and so is a blueprint, area or
      dialog whose fields name a changed script, and so on, until nothing new is added.

It errs on the side of running a test: a word in quotes that only looks like a file's name runs that test too.
What it can't see is a name put together at run time ("bank_" + sKind); the nightly run of every test is the net
for that, and for anything else this misses.
"""
import argparse
import json
import os
import re
import subprocess
import sys

TESTS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(TESTS)

# A change to any of these can change every test's result: the test harness, the build and its tools, the tests'
# own workflow, and the module's settings (its haks, its events). Other workflows, and tools/previews.sh, can't.
HARNESS = re.compile(r'^(tests/(run\.sh|compose\.yaml|tools/.*|nss/(inc_test|t_boot|t_runner)\.nss)'
                     r'|nasher\.cfg|\.github/workflows/tests\.yml|\.github/actions/.*|tools/(?!previews\.sh$).*'
                     r'|src/(.*/)?module\.ifo(\.json)?)$')
TEST_NAME = re.compile(r'^t_[a-z0-9]+_[a-z0-9_]+$')
INCLUDE = re.compile(r'^\s*#include\s+"([^"]+)"', re.M)
STRING = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
WORD = re.compile(r'[a-z0-9_]+')
COMMENT = re.compile(r'//[^\n]*|/\*.*?\*/', re.S)


def resref(path):
    return os.path.basename(path).split('.', 1)[0].lower()


def words(text, nss):
    """The words inside quotes, lower case. In a script, the includes and comments don't count."""
    if nss:
        text = INCLUDE.sub('', COMMENT.sub('', text))
    found = set()
    for s in STRING.findall(text):
        found.update(WORD.findall(s.lower()))
    return found


def read(path):
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            return f.read()
    except (FileNotFoundError, IsADirectoryError):
        return ''


def scan():
    """Every script and resource of the test module: resref -> (path, includes, words)."""
    files = {}
    for top in ('src', 'tests/nss'):
        for d, _, names in os.walk(os.path.join(ROOT, top)):
            for n in names:
                p = os.path.join(d, n)
                nss = n.endswith('.nss')
                text = read(p)
                inc = {i.lower() for i in INCLUDE.findall(text)} if nss else set()
                files.setdefault(resref(n), []).append((os.path.relpath(p, ROOT), nss, inc, words(text, nss)))
    return files


def all_tests():
    d = os.path.join(TESTS, 'nss')
    return sorted(resref(n) for n in os.listdir(d) if n.endswith('.nss') and TEST_NAME.match(resref(n)))


def changed_files(base, head):
    out = subprocess.run(['git', '-C', ROOT, 'diff', '--name-only', '--no-renames', f'{base}...{head}'],
                         check=True, capture_output=True, text=True).stdout
    return [line for line in out.splitlines() if line]


def quarantine_names(base, head):
    """Tests added to or taken off tests/quarantine.txt: they should run, to show what the change means."""
    out = subprocess.run(['git', '-C', ROOT, 'diff', f'{base}...{head}', '--', 'tests/quarantine.txt'],
                         check=True, capture_output=True, text=True).stdout
    return {m.group(1) for line in out.splitlines() if line[:1] in '+-'
            for m in [re.match(r'^[+-]\s*(t_[a-z0-9_]+)', line)] if m}


def reached(changed, files, tests):
    """The tests that reach any of the changed resrefs."""
    # Grow the changed set through the module until nothing new is added.
    affected = set(changed)
    grew = True
    while grew:
        grew = False
        for name, entries in files.items():
            if name in affected:
                continue
            for _, nss, inc, w in entries:
                if inc & affected or (not nss and w & affected):
                    affected.add(name)
                    grew = True
                    break
    picked = set()
    for t in tests:
        seen, todo, reach = set(), [t], set()
        while todo:
            n = todo.pop()
            if n in seen:
                continue
            seen.add(n)
            for _, nss, inc, w in files.get(n, []):
                if nss:
                    todo.extend(inc)
                    reach |= w
        if (seen | reach) & affected:
            picked.add(t)
    return picked


def plan(base, head):
    tests = all_tests()
    if not base:
        return 'full', tests, 'no base to compare with: every test'
    paths = changed_files(base, head)
    harness = [p for p in paths if HARNESS.match(p)]
    if harness:
        return 'full', tests, f'the harness or the build changed ({", ".join(harness[:3])}): every test'
    module = [p for p in paths if p.startswith('src/') or p.startswith('tests/nss/')]
    picked = set(quarantine_names(base, head)) & set(tests)
    if module:
        picked |= reached({resref(p) for p in module}, scan(), tests)
    if picked:
        return 'select', sorted(picked), f'{len(paths)} files changed: {len(picked)} of {len(tests)} tests reach them'
    if module:
        return 'boot', [], f'{len(module)} module files changed, and no test reaches them: build and start only'
    return 'none', [], 'nothing the test module is made of changed: no tests'


def lanes(tests, count, least):
    """Deals the tests out like cards, so each lane gets the same number, give or take one."""
    n = max(1, min(count, len(tests) // max(least, 1) or 1))
    return [tests[i::n] for i in range(n)]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--base', help='compare with this commit or branch (a pull request\'s base)')
    ap.add_argument('--head', default='HEAD')
    ap.add_argument('--lanes', type=int, default=1, help='at most this many lanes')
    ap.add_argument('--least', type=int, default=4, help='at least this many tests in a lane, or fewer lanes')
    ap.add_argument('--github-output', help='append mode=, count= and lanes= to this file')
    a = ap.parse_args()
    mode, tests, why = plan(a.base, a.head)
    split = lanes(tests, a.lanes, a.least) if tests else []
    print(f'{mode}: {why}')
    for i, lane in enumerate(split, 1):
        print(f'lane {i}: {",".join(lane)}')
    if mode == 'boot':
        matrix = [{'lane': 1, 'filter': '', 'boot': True}]
    else:
        matrix = [{'lane': i, 'filter': ','.join(lane), 'boot': False} for i, lane in enumerate(split, 1)]
    if a.github_output:
        with open(a.github_output, 'a', encoding='utf-8') as f:
            f.write(f'mode={mode}\ncount={len(tests)}\nlanes={json.dumps({"include": matrix})}\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
