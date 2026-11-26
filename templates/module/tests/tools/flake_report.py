#!/usr/bin/env python3
"""Turns the flake records of many runs into one report, in Markdown (chapter 6, tier 3).

    flake_report.py [--days 14] [--quarantine tests/quarantine.txt] FOLDER...

Each FOLDER is searched for flakes.jsonl files: the lines results.py writes for a test that failed once and passed
on a fresh server (flaky), or that failed while quarantined. The flake report workflow downloads them from the
last two weeks of runs and passes their folders here. The report has three parts:

    - every test that was flaky or failed in quarantine, most often first, with the last reason;
    - the quarantine list, with how long each test has been on it and whether it still fails;
    - lines in the quarantine list without an issue number, which the list's own rules don't allow.

It only reads; it changes nothing. Exits 0.
"""
import argparse
import datetime
import json
import os
import re
import sys


def records(folders, since):
    seen = set()
    for top in folders:
        for d, _, names in os.walk(top):
            for n in names:
                if n != 'flakes.jsonl':
                    continue
                with open(os.path.join(d, n), encoding='utf-8') as f:
                    for line in f:
                        try:
                            r = json.loads(line)
                        except ValueError:
                            continue
                        key = (r.get('test'), r.get('run'), r.get('lane'), r.get('at'))
                        if key in seen or r.get('at', '') < since:
                            continue
                        seen.add(key)
                        yield r


def quarantine(path):
    out = []
    try:
        with open(path, encoding='utf-8') as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        return out
    for line in lines:
        name, _, why = line.partition('#')
        name = name.strip()
        if name:
            date = re.search(r'\d{4}-\d{2}-\d{2}', why)
            out.append((name, why.strip(), date.group(0) if date else '', bool(re.search(r'(issue|#)\s*\d+', why))))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('folders', nargs='+')
    ap.add_argument('--days', type=int, default=14)
    ap.add_argument('--quarantine', default='tests/quarantine.txt')
    a = ap.parse_args()
    today = datetime.datetime.now(datetime.timezone.utc)
    since = (today - datetime.timedelta(days=a.days)).strftime('%Y-%m-%dT%H:%M:%SZ')
    tests = {}
    for r in records(a.folders, since):
        t = tests.setdefault(r['test'], {'flaky': 0, 'quarantined': 0, 'last': '', 'why': '', 'runs': set()})
        t[r.get('kind', 'flaky')] = t.get(r.get('kind', 'flaky'), 0) + 1
        if r.get('run'):
            t['runs'].add(r['run'])
        if r.get('at', '') >= t['last']:
            t['last'], t['why'] = r.get('at', ''), r.get('why', '')

    print(f'## Flake report: the last {a.days} days\n')
    if tests:
        print('| Test | Flaky | Failed in quarantine | Last seen | Last reason |')
        print('|---|---|---|---|---|')
        for name, t in sorted(tests.items(), key=lambda kv: -(kv[1]['flaky'] + kv[1]['quarantined'])):
            why = t['why'].replace('|', '/')[:160]
            print(f"| `{name}` | {t['flaky']} | {t['quarantined']} | {t['last'][:10]} | {why} |")
    else:
        print('No test was flaky, and no quarantined test failed. That is the goal.')

    held = quarantine(a.quarantine)
    print('\n### The quarantine list\n')
    if not held:
        print('Empty.')
    for name, why, date, has_issue in held:
        days = ''
        if date:
            days = f', on the list for {(today.date() - datetime.date.fromisoformat(date)).days} days'
        n = tests[name]['quarantined'] if name in tests else 0
        state = (f'still fails ({n} time{"s" if n > 1 else ""})' if n
                 else f'no failure recorded in {a.days} days, so it can probably come off the list')
        print(f'- `{name}`{days}: {state} ({why})')
    missing = [name for name, _, _, has_issue in held if not has_issue]
    if missing:
        print('\n### Without an issue number\n')
        for name in missing:
            print(f'- `{name}`: every quarantined test needs an issue where someone is fixing it')
    return 0


if __name__ == '__main__':
    sys.exit(main())
