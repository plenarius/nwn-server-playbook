#!/usr/bin/env python3
"""Check that a built module holds a compiled script for every script that should have one.

    check_compiled.py MODULE.mod SOURCE_FOLDER        e.g.  check_compiled.py mymodule.mod src

A script should have a compiled .ncs in the module when it has an entry point: a function called main or
StartingConditional. Scripts without one are includes and are not compiled on their own.

One case it cannot see: a script that gets its main from an include and does not mention main itself. The
compiler skips such a script without an error. Put the line "void main();" above the include in that script;
then it compiles, and this check counts it.

Why this exists: a module can be built without a script that failed to compile, and nothing in the module says
so. This looks inside the finished .mod instead of trusting the build's word. It prints the scripts that are
missing and exits 1, or prints a one-line summary and exits 0.
"""
import glob
import os
import re
import struct
import sys

ENTRY = re.compile(r'^\s*(void|int)\s+(main|StartingConditional)\s*\(', re.M)
NCS = 2010  # the resource type number of a compiled script


def compiled_scripts(path):
    """Returns the names of the compiled scripts inside a .mod file."""
    with open(path, 'rb') as f:
        data = f.read()
    if data[:8] not in (b'MOD V1.0', b'ERF V1.0', b'HAK V1.0'):
        sys.exit(f'{path}: not a module file')
    count, = struct.unpack_from('<I', data, 16)
    keys, = struct.unpack_from('<I', data, 24)
    names = set()
    for i in range(count):
        key = data[keys + i * 24:keys + i * 24 + 24]
        if struct.unpack_from('<H', key, 20)[0] == NCS:
            names.add(key[:16].split(b'\0')[0].decode('latin-1').lower())
    return names


def strip_comments(src):
    """Returns src without // and /* */ comments. Text inside quotes is kept as it is."""
    out = []
    i, n = 0, len(src)
    while i < n:
        if src[i] == '"':
            j = i + 1
            while j < n and src[j] not in '"\n':
                j += 2 if src[j] == '\\' else 1
            out.append(src[i:j + 1])
            i = j + 1
        elif src.startswith('//', i):
            j = src.find('\n', i)
            i = n if j < 0 else j
        elif src.startswith('/*', i):
            j = src.find('*/', i + 2)
            i = n if j < 0 else j + 2
        else:
            out.append(src[i])
            i += 1
    return ''.join(out)


def main(module, source):
    have = compiled_scripts(module)
    wanted = []
    for path in sorted(glob.glob(os.path.join(source, '**', '*.nss'), recursive=True)):
        with open(path, encoding='latin-1') as f:
            if ENTRY.search(strip_comments(f.read())):
                wanted.append(os.path.basename(path)[:-4].lower())
    missing = [name for name in wanted if name not in have]
    if missing:
        print(f'{module} has no compiled script for {len(missing)} of {len(wanted)} scripts:')
        for name in missing:
            print(f'  {name}.nss')
        return 1
    print(f'{module}: every script with an entry point is compiled ({len(wanted)} checked)')
    return 0


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2]))
