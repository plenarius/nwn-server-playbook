#!/usr/bin/env python3
"""Check that the test server has every hak and the talk table the module lists, before it starts.

    check_content.py MODULE.mod HAK_FOLDER TLK_FOLDER

Without them the server stops at once with "Unable to load module", which says nothing about why. This reads the
module's own list (module.ifo inside the .mod) and names what is missing instead. Exits 1 if anything is.
"""
import os
import struct
import sys

IFO = 2014  # the resource type number of module.ifo


def module_ifo(path):
    """Returns the bytes of module.ifo from a .mod file."""
    with open(path, 'rb') as f:
        data = f.read()
    if data[:8] not in (b'MOD V1.0', b'ERF V1.0'):
        sys.exit(f'{path}: not a module file')
    count, = struct.unpack_from('<I', data, 16)
    keys, resources = struct.unpack_from('<II', data, 24)
    for i in range(count):
        name = data[keys + i * 24:keys + i * 24 + 16].split(b'\0')[0].lower()
        resid, restype = struct.unpack_from('<IH', data, keys + i * 24 + 16)
        if name == b'module' and restype == IFO:
            offset, size = struct.unpack_from('<II', data, resources + resid * 8)
            return data[offset:offset + size]
    sys.exit(f'{path}: has no module.ifo')


def gff_fields(data, struct_index):
    """Returns {label: (type, value)} for one struct of a GFF file. Strings and lists only; enough for an ifo."""
    (s_off, _, f_off, _, l_off, _, d_off, _, i_off, _, li_off, _) = struct.unpack_from('<12I', data, 8)
    _, s_data, s_count = struct.unpack_from('<III', data, s_off + struct_index * 12)
    if s_count == 1:
        indices = [s_data]
    else:
        indices = struct.unpack_from(f'<{s_count}I', data, i_off + s_data)
    fields = {}
    for fi in indices:
        ftype, label, value = struct.unpack_from('<III', data, f_off + fi * 12)
        name = data[l_off + label * 16:l_off + label * 16 + 16].split(b'\0')[0].decode('latin-1')
        if ftype == 10:  # a string
            size, = struct.unpack_from('<I', data, d_off + value)
            fields[name] = data[d_off + value + 4:d_off + value + 4 + size].decode('latin-1')
        elif ftype == 11:  # a resref
            fields[name] = data[d_off + value + 1:d_off + value + 1 + data[d_off + value]].decode('latin-1')
        elif ftype == 15:  # a list of structs
            n, = struct.unpack_from('<I', data, li_off + value)
            fields[name] = list(struct.unpack_from(f'<{n}I', data, li_off + value + 4))
    return fields


def main(module, hak_dir, tlk_dir):
    ifo = module_ifo(module)
    top = gff_fields(ifo, 0)
    haks = [gff_fields(ifo, i).get('Mod_Hak', '') for i in top.get('Mod_HakList', [])]
    if not haks and top.get('Mod_Hak'):  # modules from before the list kept one hak here
        haks = [top['Mod_Hak']]
    wanted = [os.path.join(hak_dir, f'{h.lower()}.hak') for h in haks if h]
    if top.get('Mod_CustomTlk'):
        wanted.append(os.path.join(tlk_dir, f"{top['Mod_CustomTlk'].lower()}.tlk"))
    missing = [path for path in wanted if not os.path.isfile(path)]
    for path in missing:
        print(f'the module needs {os.path.basename(path)}, and the test server has no {path}')
    if missing:
        print('give it your content with --content (chapter 6, step 16); if this change needs new content, stage it first')
        return 1
    return 0


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    sys.exit(main(*sys.argv[1:]))
