#!/usr/bin/env python3
"""Check the built 32-bit adapters do not require iOS 8-only symbols at startup."""
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]


def inspect(path):
    data = path.read_bytes()
    magic, cpu, subtype, _, count = struct.unpack_from('<IIIII', data)
    assert (magic, cpu, subtype) == (0xfeedface, 12, 9), path.name
    cursor = 28
    symbol_table = None
    libraries = []
    for _ in range(count):
        command, size = struct.unpack_from('<II', data, cursor)
        assert size >= 8 and cursor + size <= len(data)
        if command == 2:
            symbol_table = struct.unpack_from('<IIII', data, cursor + 8)
        if command in (0xc, 0x80000018, 0x8000001f, 0x80000023):
            name_offset = struct.unpack_from('<I', data, cursor + 8)[0]
            libraries.append(data[cursor + name_offset:cursor + size].split(b'\0', 1)[0].decode())
        cursor += size
    assert symbol_table is not None
    symbols, entries, strings, string_size = symbol_table
    assert strings + string_size <= len(data)
    imports = set()
    for i in range(entries):
        index, kind, section, _, _ = struct.unpack_from('<IBBHI', data, symbols + i * 12)
        if kind & 0x0e == 0 and section == 0 and index:
            imports.add(data[strings + index:strings + string_size].split(b'\0', 1)[0].decode())
    forbidden = {'_objc_initWeak', '_objc_loadWeakRetained', '_objc_destroyWeak',
                 '_OBJC_CLASS_$_WKWebView', '_OBJC_CLASS_$_WKNavigationAction',
                 '_OBJC_CLASS_$_WKNavigationResponse', '_OBJC_CLASS_$_LSApplicationWorkspace',
                 '_OBJC_CLASS_$_UIUserNotificationSettings'}
    assert not (imports & forbidden), (path.name, imports & forbidden)
    assert not any('/WebKit.framework/' in p or '/MobileInstallation.framework/' in p for p in libraries), libraries
    print('PASS:', path.name, 'is armv7 with no startup dependency on WKWebView, iOS 8 workspace or zeroing-weak entry points')


if __name__ == '__main__':
    inspect(ROOT / 'build/Receptor.dylib')
    inspect(ROOT / 'build/Receptor.app/ReceptorApp')
