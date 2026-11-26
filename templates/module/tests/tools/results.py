#!/usr/bin/env python3
"""Reads the test server's log, prints the results, writes junit.xml, and exits 1 if anything failed.

    results.py LOG_FOLDER junit.xml

The runner (tests/nss/t_runner.nss) writes one TEST|<event>|<test>|<detail> line for each step into the server's
log (nwserverLog1.txt). Script errors go to the engine's log (nwengineLog.txt) instead, with the script's name.
A run fails when a test failed, when any script stopped on an error (in a test: that test fails; anywhere else:
the run fails), or when the runner never reached its last line (END): a server that crashed or hung half-way must
never look like a pass.
"""
import os
import re
import sys
from xml.sax.saxutils import escape, quoteattr

LINE = re.compile(r'TEST\|(BOOT|FOUND|START|ASSERT|PASS|FAIL|SKIP|END)\|([^|\r\n]*)\|([^\r\n]*)')
# What the game writes when a script stops on an error (division by zero, too many instructions and so on).
SCRIPT_ERROR = re.compile(r'Script error: ([A-Za-z0-9_]+) OID: [^,]*, Tag: [^,]*, ERROR: (.*)')


def read(path):
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            return f.read().splitlines()
    except FileNotFoundError:
        return []


def main(log_dir, junit_path):
    lines = read(os.path.join(log_dir, 'nwserverLog1.txt'))
    tests = {}       # name -> {'result', 'detail', 'asserts': [...], 'errors': [...]}
    order = []
    current = None
    ended = False
    for line in lines:
        m = LINE.search(line)
        if m:
            event, name, detail = m.groups()
            if event == 'START':
                current = name
                order.append(name)
                tests[name] = {'result': None, 'detail': '', 'asserts': [], 'errors': []}
            elif event == 'ASSERT' and name in tests:
                tests[name]['asserts'].append(detail)
            elif event in ('PASS', 'FAIL', 'SKIP') and name in tests:
                tests[name]['result'] = event
                tests[name]['detail'] = detail
                current = None
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

    failed = 0
    cases = []
    for name in order:
        t = tests[name]
        if t['errors'] and t['result'] != 'SKIP':
            t['result'] = 'FAIL'   # a script error fails a test even if its asserts passed
            t['detail'] = ''
        if t['result'] is None:
            t['result'] = 'FAIL'
            t['detail'] = 'never finished'
        why = '; '.join(t['asserts'] + t['errors'] + ([t['detail']] if t['detail'] else []))
        print(f"{t['result']:4}  {name}" + (f'  ({why})' if t['result'] != 'PASS' and why else ''))
        body = ''
        if t['result'] == 'FAIL':
            failed += 1
            body = f'<failure message={quoteattr(why)}>{escape(why)}</failure>'
        elif t['result'] == 'SKIP':
            body = f'<skipped message={quoteattr(t["detail"])}/>'
        cases.append(f'  <testcase classname="tests" name={quoteattr(name)}>{body}</testcase>')
    skipped = sum(1 for n in order if tests[n]['result'] == 'SKIP')
    problems = [f'script error in {e}' for e in other_errors]
    if not ended:
        problems.append('the runner never finished: look at the logs in ' + log_dir)
    if problems:
        failed += 1
        why = '; '.join(problems)
        print(f'FAIL  the run itself  ({why})')
        cases.append(f'  <testcase classname="tests" name="the run itself">'
                     f'<failure message={quoteattr(why)}>{escape(why)}</failure></testcase>')
    with open(junit_path, 'w', encoding='utf-8') as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
        f.write(f'<testsuite name="tests" tests="{len(cases)}" failures="{failed}" skipped="{skipped}">\n')
        f.write('\n'.join(cases) + '\n</testsuite>\n')
    passed = sum(1 for n in order if tests[n]['result'] == 'PASS')
    print(f'{passed} passed, {failed} failed, {skipped} skipped' + ('' if ended else ' (the run did not finish)'))
    return 1 if failed or not order else 0


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2]))
