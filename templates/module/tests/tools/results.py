#!/usr/bin/env python3
"""Reads the test server's log, prints the results, writes junit.xml, and exits 1 if anything failed.

    results.py LOG_FOLDER junit.xml [options]

    --failed                 print only the names of the tests that failed and may be run again (comma-separated)
    --retry-logs FOLDER      the logs of a second run of the failed tests on a fresh server (run.sh --retry)
    --quarantine FILE        tests whose failure is reported but doesn't fail the run (tests/quarantine.txt)
    --flakes FILE            add a JSON line here for each test that failed once and passed again, or failed
                             while quarantined: the record the flake report is made from
    --json FILE              every test's result, for a workflow that joins several lanes
    --allow-empty            a run of no tests at all is fine (run.sh --boot-only)

The runner (tests/nss/t_runner.nss) writes one TEST|<event>|<test>|<detail> line for each step into the server's
log (nwserverLog1.txt). Script errors go to the engine's log (nwengineLog.txt) instead, with the script's name.
A run fails when a test failed, when any script stopped on an error (in a test: that test fails; anywhere else:
the run fails), or when the runner never reached its last line (END): a server that crashed or hung half-way must
never look like a pass.

Two results besides PASS, FAIL and SKIP (chapter 6, tier 3):
    FLAKY        failed, then passed when run again on a fresh server. The run passes, says so loudly, and
                 writes the record down
    QUARANTINED  failed, and is on the quarantine list: reported and recorded, but the run doesn't fail for it
"""
import argparse
import datetime
import json
import os
import re
import subprocess
import sys
from xml.sax.saxutils import escape, quoteattr

LINE = re.compile(r'TEST\|(BOOT|FOUND|START|ASSERT|PASS|FAIL|SKIP|END)\|([^|\r\n]*)\|([^\r\n]*)')
# What the game writes when a script stops on an error (division by zero, too many instructions and so on).
SCRIPT_ERROR = re.compile(r'Script error: ([A-Za-z0-9_]+) OID: [^,]*, Tag: [^,]*, ERROR: (.*)')
# At most this many failed tests are run again; more than that is a real break, not bad luck.
RETRY_MOST = 5


def read(path):
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            return f.read().splitlines()
    except FileNotFoundError:
        return []


def parse(log_dir):
    """Returns (tests in order as {name: {result, why}}, problems of the run itself)."""
    tests, order, ended = {}, [], False
    for line in read(os.path.join(log_dir, 'nwserverLog1.txt')):
        m = LINE.search(line)
        if not m:
            continue
        event, name, detail = m.groups()
        if event == 'START':
            order.append(name)
            tests[name] = {'result': None, 'detail': '', 'asserts': [], 'errors': []}
        elif event == 'ASSERT' and name in tests:
            tests[name]['asserts'].append(detail)
        elif event in ('PASS', 'FAIL', 'SKIP') and name in tests:
            tests[name]['result'] = event
            tests[name]['detail'] = detail
        elif event == 'END':
            ended = True
    other_errors = []
    for line in read(os.path.join(log_dir, 'nwengineLog.txt')):
        e = SCRIPT_ERROR.search(line)
        if not e:
            continue
        script, error = e.group(1).lower(), e.group(2).strip()
        if script in tests:
            tests[script]['errors'].append(f'script error: {error}')
        else:
            other_errors.append(f'{script}: {error}')
    results = {}
    for name in order:
        t = tests[name]
        if t['errors'] and t['result'] != 'SKIP':
            t['result'], t['detail'] = 'FAIL', ''   # a script error fails a test even if its asserts passed
        if t['result'] is None:
            t['result'], t['detail'] = 'FAIL', 'never finished'
        why = '; '.join(t['asserts'] + t['errors'] + ([t['detail']] if t['detail'] else []))
        results[name] = {'result': t['result'], 'why': why}
    problems = [f'script error in {e}' for e in other_errors]
    if not ended:
        problems.append('the runner never finished: look at the logs in ' + log_dir)
    return results, problems


def quarantined(path):
    """The names on the quarantine list. Each line: a test's name, then # and why (an issue number)."""
    names = set()
    for line in read(path) if path else []:
        name = line.split('#', 1)[0].strip()
        if name:
            names.add(name)
    return names


def commit():
    sha = os.environ.get('GITHUB_SHA')
    if sha:
        return sha
    try:
        return subprocess.run(['git', 'rev-parse', 'HEAD'], capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return ''


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('log_dir')
    ap.add_argument('junit')
    ap.add_argument('--failed', action='store_true')
    ap.add_argument('--retry-logs')
    ap.add_argument('--quarantine')
    ap.add_argument('--flakes')
    ap.add_argument('--json')
    ap.add_argument('--allow-empty', action='store_true')
    a = ap.parse_args()

    results, problems = parse(a.log_dir)
    held = quarantined(a.quarantine)
    if a.failed:
        # Only when the run itself was sound: a crash is not something a second try should hide.
        failed = [n for n, r in results.items() if r['result'] == 'FAIL' and n not in held]
        if not problems and 0 < len(failed) <= RETRY_MOST:
            print(','.join(failed))
        return 0

    records = []
    now = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    where = {'commit': commit(), 'run': os.environ.get('GITHUB_RUN_ID', ''),
             'lane': os.environ.get('TEST_LANE', ''), 'at': now}
    if a.retry_logs:
        again, again_problems = parse(a.retry_logs)
        for name, r in again.items():
            first = results.get(name)
            if not first or first['result'] != 'FAIL':
                continue
            if r['result'] == 'PASS':
                first.update(result='FLAKY', why=f'failed, then passed on a fresh server; the first time: {first["why"]}')
                records.append({'test': name, 'kind': 'flaky', 'why': first['why'], **where})
            else:
                first['why'] += f'; failed again on a fresh server: {r["why"]}'
        problems += [f'on the second try: {p}' for p in again_problems]
    for name, r in results.items():
        if name in held:
            if r['result'] == 'FAIL':
                r['result'] = 'QUARANTINED'
                r['why'] = f'failed, and is quarantined: {r["why"]}'
                records.append({'test': name, 'kind': 'quarantined', 'why': r['why'], **where})
            elif r['result'] == 'PASS':
                r['why'] = 'passed, and is quarantined: take it off the list once it keeps passing'

    failed = 0
    cases = []
    for name, r in results.items():
        res, why = r['result'], r['why']
        shown = why if res != 'PASS' or name in held else ''
        print(f'{res:4}  {name}' + (f'  ({shown})' if shown else ''))
        body = ''
        if res == 'FAIL':
            failed += 1
            body = f'<failure message={quoteattr(why)}>{escape(why)}</failure>'
        elif res in ('SKIP', 'QUARANTINED'):
            body = f'<skipped message={quoteattr(why)}/>'
        elif res == 'FLAKY':
            body = f'<system-out>{escape("FLAKY: " + why)}</system-out>'
        cases.append(f'  <testcase classname="tests" name={quoteattr(name)}>{body}</testcase>')
    if problems:
        failed += 1
        why = '; '.join(problems)
        print(f'FAIL  the run itself  ({why})')
        cases.append(f'  <testcase classname="tests" name="the run itself">'
                     f'<failure message={quoteattr(why)}>{escape(why)}</failure></testcase>')
    count = {k: sum(1 for r in results.values() if r['result'] == k) for k in ('PASS', 'SKIP', 'FLAKY', 'QUARANTINED')}
    with open(a.junit, 'w', encoding='utf-8') as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
        f.write(f'<testsuite name="tests" tests="{len(cases)}" failures="{failed}" '
                f'skipped="{count["SKIP"] + count["QUARANTINED"]}">\n')
        f.write('\n'.join(cases) + '\n</testsuite>\n')
    if a.json:
        with open(a.json, 'w', encoding='utf-8') as f:
            json.dump({'tests': results, 'problems': problems, **where}, f, indent=1)
    if a.flakes and records:
        with open(a.flakes, 'a', encoding='utf-8') as f:
            for rec in records:
                f.write(json.dumps(rec) + '\n')
    flaky = f' ({count["FLAKY"]} of them only on a second try)' if count['FLAKY'] else ''
    held_n = f', {count["QUARANTINED"]} failed in quarantine' if count['QUARANTINED'] else ''
    print(f'{count["PASS"] + count["FLAKY"]} passed{flaky}, {failed} failed, {count["SKIP"]} skipped{held_n}')
    if count['FLAKY']:
        print(f'WARNING: {count["FLAKY"]} test(s) passed only on a second try. That is a flaky test, not a pass to '
              'forget: look at the flake report, and fix it or quarantine it with an issue number.')
    if not results and not a.allow_empty:
        return 1
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
