#!/usr/bin/env python3
"""Run production 3.2 Foundation adapters and disabled-background helper fixtures."""
import os
from pathlib import Path
import plistlib
import shlex
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
def main():
    flags=shlex.split(subprocess.check_output(['gnustep-config','--objc-flags'],text=True));libs=shlex.split(subprocess.check_output(['gnustep-config','--base-libs'],text=True))
    with tempfile.TemporaryDirectory(prefix='receptor32-foundation-') as temp:
        base=Path(temp);probe=base/'probe'
        common=['gcc',*flags,'-std=gnu99','-Werror','-Wno-unused-function','-DRC_LEGACY32=1','-include',str(ROOT/'RCCompatibility32.h')]
        subprocess.run([*common,str(ROOT/'tests/legacy32_foundation_probe.m'),str(ROOT/'RCCompatibility32.m'),'-o',str(probe),*libs],check=True)
        subprocess.run([str(probe)],check=True)
        for name in ['downloads','var/tmp']:(base/name).mkdir(parents=True)
        defines=['-DRC_PACKAGE_TEST=1',f'-DRC_PKG_TEST_ROOT="{base}"',f'-DRC_CALLER_UID={os.getuid()}',f'-DRC_LOCK_OWNER={os.getuid()}',
                 *[f'-D{name}="{base/relative}"' for name,relative in {'RC_DOWNLOADS_DIR':'downloads','RC_STAGING_PARENT':'var/tmp','RC_DPKG_BINARY':'missing-dpkg','RC_LAUNCHCTL_BINARY':'missing-launchctl','RC_DPKG_LOCK':'dpkg.lock','RC_OPERATION_LOCK':'var/tmp/receptor-packages.lock'}.items()]]
        helper=base/'helper'
        subprocess.run([*common,*defines,str(ROOT/'Tools/receptor-package-helper.m'),str(ROOT/'RCCompatibility32.m'),'-o',str(helper),*libs,'-lcrypto'],check=True)
        def run(*args):return plistlib.loads(subprocess.check_output([str(helper),*args],timeout=5))
        assert run('remote-status')['enabled'] is False and run('remote-disable')['enabled'] is False
        assert 'disabled' in run('remote-start')['error'] and 'disabled' in run('remote-enable','ignored.plist')['error']
        assert not (base/'var/lib/receptor').exists()
        print('PASS: the 3.2 package helper refuses background enrollment/start, reports disabled and performs no launchctl or daemon configuration')
if __name__=='__main__':main()
