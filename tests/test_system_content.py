#!/usr/bin/env python3
"""Linux/WSL: execute the production Safari installer-content classifier."""
import ctypes
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    library = ROOT / 'build/libreceptor-system-content.so'
    library.parent.mkdir(exist_ok=True)
    subprocess.run(['cc', '-shared', '-fPIC', '-Wall', '-Wextra', '-Werror',
                    str(ROOT / 'RCSystemContent.c'), '-o', str(library)], check=True)
    classify = ctypes.CDLL(str(library)).RCIsSystemInstallerContent
    classify.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    classify.restype = ctypes.c_int
    for extension in [b'mobileconfig', b'MOBILECONFIG', b'cer', b'crt', b'DER', b'p12', b'PFX']:
        assert classify(extension, b'application/octet-stream') == 1
    for mime in [b'application/x-apple-aspen-config', b' Application/X-Apple-Aspen-Config ; charset=utf-8',
                 b'application/x-x509-ca-cert', b'application/pkix-cert', b'application/x-x509-user-cert',
                 b'application/x-pkcs12', b'application/pkcs12']:
        assert classify(b'php', mime) == 1
    for extension in [b'zip', b'ipa', b'deb', b'png', b'plist', b'pem', b'mobileconfig.zip', b'cer.txt', b'']:
        assert classify(extension, b'application/octet-stream') == 0
    for mime in [None, b'', b'text/plain', b'application/x-apple-aspen-config-extra',
                 b'application/pkcs12-not-really', b'application/octet-stream; filename=x.mobileconfig']:
        assert classify(None, mime) == 0
    print('PASS: native installer extensions/MIMEs (including case/parameters) bypass downloads; ordinary files and lookalikes do not')


if __name__ == '__main__':
    main()
