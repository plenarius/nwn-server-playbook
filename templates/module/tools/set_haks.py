#!/usr/bin/env python3
"""Write the module's list of haks and its talk table into the module's settings file.

    set_haks.py [--tlk NAME] HAK...        e.g.  set_haks.py --tlk my_tlk top_hak base_hak
    set_haks.py --show

Names are given without ".hak" and ".tlk". The order matters: when two haks hold a file of the same name, the
hak named first wins. It edits src/ifo/module.ifo.json in the current folder, which is where "nasher unpack"
puts it. The toolset does the same thing under Module Properties, Custom Content; this is for doing it in text.
"""
import json
import sys

IFO = 'src/ifo/module.ifo.json'


def main(args):
    with open(IFO, encoding='utf-8') as f:
        ifo = json.load(f)
    if args == ['--show']:
        print('talk table:', ifo['Mod_CustomTlk']['value'] or '(none)')
        for entry in ifo['Mod_HakList']['value']:
            print('hak:', entry['Mod_Hak']['value'])
        return 0
    tlk = None
    if args[:1] == ['--tlk']:
        tlk, args = args[1], args[2:]
    for name in args + ([tlk] if tlk else []):
        if name.endswith(('.hak', '.tlk')) or len(name) > 16:
            sys.exit(f'{name}: give the name without its extension, at most 16 characters')
    ifo['Mod_HakList'] = {'type': 'list', 'value': [
        {'__struct_id': 8, 'Mod_Hak': {'type': 'cexostring', 'value': name}} for name in args]}
    if tlk is not None:
        ifo['Mod_CustomTlk'] = {'type': 'cexostring', 'value': tlk}
    with open(IFO, 'w', encoding='utf-8') as f:
        json.dump(ifo, f, indent=2, ensure_ascii=False)
        f.write('\n')
    print(f'{IFO}: {len(args)} hak(s), talk table {ifo["Mod_CustomTlk"]["value"] or "(none)"}')
    return 0


if __name__ == '__main__':
    if len(sys.argv) < 2 or sys.argv[1] in ('-h', '--help'):
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1:]))
