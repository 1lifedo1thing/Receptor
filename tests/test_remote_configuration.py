#!/usr/bin/env python3
"""Production configuration validation under GNUstep; no launchd/network calls."""
import fcntl
import os
from pathlib import Path
import plistlib
import shlex
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix='receptor-remote-config-') as temp:
        base=Path(temp)
        for directory in ['downloads','var/tmp','var/lib']:(base/directory).mkdir(parents=True,exist_ok=True)
        common=shlex.split(subprocess.check_output(['gnustep-config','--objc-flags'],text=True))
        libs=shlex.split(subprocess.check_output(['gnustep-config','--base-libs'],text=True))
        defs=['-DRC_PACKAGE_TEST=1','-DRC_REMOTE_HOST_TEST=1',f'-DRC_PKG_TEST_ROOT="{base}"',f'-DRC_REMOTE_TEST_ROOT="{base}"',f'-DRC_CALLER_UID={os.getuid()}',f'-DRC_LOCK_OWNER={os.getuid()}',
              *[f'-D{name}="{base/relative}"' for name,relative in {'RC_DOWNLOADS_DIR':'downloads','RC_STAGING_PARENT':'var/tmp','RC_DPKG_BINARY':'fake-dpkg','RC_LAUNCHCTL_BINARY':'fake-launchctl','RC_DPKG_LOCK':'dpkg.lock','RC_OPERATION_LOCK':'var/tmp/receptor-packages.lock'}.items()]]
        helper=base/'helper'
        subprocess.run(['gcc',*common,'-std=gnu99','-Werror','-Wno-unused-function',*defs,str(ROOT/'Tools/receptor-package-helper.m'),str(ROOT/'RCRemoteCrypto.m'),str(ROOT/'RCRemoteSupport.m'),'-o',str(helper),*libs,'-lcrypto'],check=True)
        private=base/'key.pem';public=base/'public.pem';seed=os.urandom(32)
        subprocess.run(['openssl','genpkey','-algorithm','RSA','-pkeyopt','rsa_keygen_bits:2048','-out',str(private)],check=True,capture_output=True)
        subprocess.run(['openssl','pkey','-in',str(private),'-pubout','-out',str(public)],check=True,capture_output=True)
        sealed=subprocess.run(['openssl','pkeyutl','-encrypt','-pubin','-inkey',str(public),'-pkeyopt','rsa_padding_mode:oaep'],input=seed,capture_output=True,check=True).stdout
        value={'host':'192.168.1.20:49176','seed':seed,'sealed':sealed,'publicKey':public.read_text(),'enrollment':'1'*64}
        staged=base/'downloads/.receptor-remote-config-fixture.plist'
        def stage(config=None,mode=0o600):staged.write_bytes(plistlib.dumps(config or value));staged.chmod(mode)
        def run(*args):
            process=subprocess.run([str(helper),*args],capture_output=True,timeout=10)
            assert process.returncode==0,process.stderr.decode(errors='replace')
            return plistlib.loads(process.stdout)
        assert run('remote-status')['enabled'] is False
        stage();assert run('remote-enable',staged.name)['enabled'] is True
        config=base/'var/lib/receptor/remote.plist'
        saved=plistlib.loads(config.read_bytes());assert saved['seed']==seed and config.stat().st_mode&0o077==0
        assert not staged.exists()
        status=run('remote-status');assert status['enabled'] and status['host']==value['host']
        assert all(field not in status for field in ['seed','sealed','enrollment','publicKey'])
        print('PASS: explicit setup saves a private per-device secret, removes staged credentials and exposes only redacted background status')
        original=config.read_bytes()
        for change in [{'host':'8.8.8.8:80'},{'host':'192.168.1.20:0'},{'host':'user:password@192.168.1.20:80'},{'seed':b'bad'},{'sealed':b'bad'},{'publicKey':'bad key'},{'enrollment':'bad'}]:
            bad=dict(value,**change);stage(bad);assert 'error' in run('remote-enable',staged.name);assert config.read_bytes()==original
        stage(mode=0o644);assert 'error' in run('remote-enable',staged.name)
        staged.unlink();staged.symlink_to(config);assert 'error' in run('remote-enable',staged.name)
        assert 'error' in run('remote-enable','../escape.plist')
        print('PASS: public addresses, invalid ports/credentials/keys/proofs, unsafe modes, symlinks and arbitrary setup paths are refused')
        lock=base/'var/tmp/receptor-packages.lock'
        with lock.open('r+') as file:
            fcntl.flock(file,fcntl.LOCK_EX|fcntl.LOCK_NB)
            assert run('remote-status')['enabled']
            assert run('remote-disable')['enabled'] is False
        assert not config.exists()
        assert run('remote-disable')['enabled'] is False
        print('PASS: revocation and redacted status remain available during another package operation; repeated disable is safe')


if __name__=='__main__':main()
