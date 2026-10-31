#!/usr/bin/env python3
"""Run on Linux/WSL with cc and OpenSSL headers; exercise the production C loop."""
import ctypes
import hashlib
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    output = ROOT / 'build/libreceptor-pairing.so'
    output.parent.mkdir(exist_ok=True)
    subprocess.run(['cc', '-shared', '-fPIC', '-DRC_PAIRING_HOST_TEST', '-O2',
                    str(ROOT / 'RCPairingCrypto.c'), '-lcrypto', '-o', str(output)], check=True)
    library = ctypes.CDLL(str(output))
    library.RCPairingDerive.argtypes = [ctypes.c_char_p, ctypes.c_void_p, ctypes.c_void_p]
    library.RCPairingDerive.restype = None
    for code, salt in [(b'ABCDEFGH', bytes(range(16))), (b'23456789', bytes(16)),
                       (b'ZZZZZZZZ', b'\xff' * 16)]:
        actual = ctypes.create_string_buffer(32)
        library.RCPairingDerive(code, ctypes.create_string_buffer(salt), actual)
        assert actual.raw == hashlib.pbkdf2_hmac('sha256', code, salt, 100000)
    print('PASS: production C key derivation matches three independent PBKDF2-HMAC-SHA256 vectors')


if __name__ == '__main__':
    main()
