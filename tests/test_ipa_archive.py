#!/usr/bin/env python3
"""Linux/WSL: exercise the production bounded IPA Info.plist reader, without extraction."""
import ctypes
import io
from pathlib import Path
import plistlib
import random
import struct
import subprocess
import tempfile
import warnings
import zipfile

ROOT = Path(__file__).resolve().parents[1]
INFO = plistlib.dumps({'CFBundleIdentifier': 'com.receptor.fixture', 'CFBundleVersion': '1.0'})


def archive(entries, compression=zipfile.ZIP_DEFLATED, comment=b''):
    output = io.BytesIO()
    with warnings.catch_warnings():
        warnings.simplefilter('ignore', UserWarning)
        with zipfile.ZipFile(output, 'w', compression=compression) as z:
            for name, body in entries: z.writestr(name, body)
            z.comment = comment
    return output.getvalue()


def main():
    output = ROOT / 'build/libreceptor-ipa.so'
    output.parent.mkdir(exist_ok=True)
    subprocess.run(['cc', '-shared', '-fPIC', '-O2', '-Wall', '-Wextra', '-Werror',
                    str(ROOT / 'RCIPAArchive.c'), '-lz', '-o', str(output)], check=True)
    lib = ctypes.CDLL(str(output)); free = ctypes.CDLL(None).free
    free.argtypes = [ctypes.c_void_p]
    lib.RCIPAReadInfoPlist.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(ctypes.c_size_t)]
    lib.RCIPAReadInfoPlist.restype = ctypes.c_int
    with tempfile.TemporaryDirectory(prefix='receptor-ipa-test-') as temporary:
        path = Path(temporary) / 'fixture.ipa'

        def read(data):
            path.write_bytes(data)
            buffer = ctypes.c_void_p(); size = ctypes.c_size_t()
            result = lib.RCIPAReadInfoPlist(str(path).encode(), ctypes.byref(buffer), ctypes.byref(size))
            if result:
                try: return ctypes.string_at(buffer, size.value)
                finally: free(buffer)
            assert not buffer.value and size.value == 0
            return None

        entry = ('Payload/Test.app/Info.plist', INFO)
        for compression in [zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED]:
            assert read(archive([('Payload/Test.app/other.bin', b'bytes'), entry], compression)) == INFO
        binary = plistlib.dumps({'CFBundleIdentifier': 'com.receptor.fixture'}, fmt=plistlib.FMT_BINARY)
        assert read(archive([('Payload/Test.app/Info.plist', binary)], comment=b'ZIP comment PK\x05\x06')) == binary
        class NonSeekable(io.BytesIO):
            def seekable(self): return False
            def seek(self, *args): raise io.UnsupportedOperation()
        stream = NonSeekable()
        with zipfile.ZipFile(stream, 'w', compression=zipfile.ZIP_DEFLATED) as z: z.writestr(*entry)
        assert read(stream.getvalue()) == INFO
        print('PASS: stored/deflated XML and binary plists, comments and data descriptors preserve exact bytes')

        invalid = [b'', b'not a ZIP', archive([]), archive([('Payload/Test.app/nested/Info.plist', INFO)]),
                   archive([('Payload/../Test.app/Info.plist', INFO)]), archive([entry, entry]),
                   archive([entry, ('Payload/Other.app/Info.plist', INFO)]), archive([entry], zipfile.ZIP_BZIP2),
                   archive([('Payload/Test.app/Info.plist', b'x' * (2 * 1024 * 1024 + 1))])]
        original = archive([entry])
        central, end = original.index(b'PK\x01\x02'), original.rindex(b'PK\x05\x06')
        for offset, fmt, value in [(central + 8, '<H', 1), (central + 24, '<I', 0xffffffff),
                                   (central + 42, '<I', len(original) + 1), (end + 4, '<H', 1),
                                   (end + 10, '<H', 0xffff), (central + 16, '<I', 0), (end + 16, '<I', 0xfffffffe)]:
            changed = bytearray(original); struct.pack_into(fmt, changed, offset, value); invalid.append(changed)
        changed = bytearray(original); changed[30 + 8] ^= 1; invalid.append(changed)  # Local/central name mismatch.
        invalid.extend([original[:-1], original[:central], original + b'trailing garbage'])
        for data in invalid: assert read(data) is None
        print('PASS: truncation, ambiguity, traversal roots, encryption, unsupported compression, ZIP64, bad bounds/CRC and oversized plists rejected')

        rng = random.Random(5718)
        for _ in range(1000):
            changed = bytearray(original)
            for __ in range(rng.randint(1, 5)):
                position = rng.randrange(len(changed)); changed[position] ^= rng.randrange(1, 256)
            result = read(changed)
            assert result is None or len(result) <= 2 * 1024 * 1024
        print('PASS: 1000 deterministic malformed-archive mutations remain bounded and cleanly return')


if __name__ == '__main__': main()
