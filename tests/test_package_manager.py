#!/usr/bin/env python3
"""Run the production Objective-C package helper under GNUstep with fake APT.

Test mode is forbidden on Apple. Every path is redirected to a private fixture;
the host package database and network are never used by the tested helper.
"""
import fcntl
import json
import os
from pathlib import Path
import plistlib
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix='receptor-packages-') as temporary:
        fixture = Path(temporary)
        for directory in ['usr/bin', 'var/tmp', 'var/lib/dpkg', 'var/lib/cydia', 'etc/apt/sources.list.d', 'var/mobile/Library/Preferences']:
            (fixture / directory).mkdir(parents=True, exist_ok=True)
        status = fixture / 'var/lib/dpkg/status'
        status.write_text('Package: example.tweak\nName: Example Tweak\nVersion: 1.0\nStatus: install ok installed\nDescription: A fixture\n\nPackage: core.system\nVersion: 1.0\nStatus: install ok installed\nEssential: yes\n\n')
        config = fixture / 'config.json'
        record = fixture / 'commands.json'
        config.write_text('{}')
        fake = '#!/usr/bin/python3 -I\n' + f'ROOT={str(fixture)!r}\n' + r'''
import json, os, pathlib, sys
root=pathlib.Path(ROOT); cfg=json.loads((root/'config.json').read_text())
assert 'RC_INJECTED' not in os.environ and 'DPKG_ROOT' not in os.environ
assert os.environ['LC_ALL']=='C' and os.environ['DEBIAN_FRONTEND']=='noninteractive'
assert sys.stdin.read()==''
record=root/'commands.json'; calls=json.loads(record.read_text()) if record.exists() else []
args=sys.argv[1:]; calls.append([pathlib.Path(sys.argv[0]).name,args]); record.write_text(json.dumps(calls))
if pathlib.Path(sys.argv[0]).name=='apt-cache':
 if args[0]=='policy': print(args[1]+':\n  Installed: 1.0\n  Candidate: '+cfg.get('candidate','2.0'))
 elif args[0]=='search': print('example.tweak - A fixture\nsecond.tweak - Another fixture')
 elif args[0]=='show': print('Package: '+args[1]+'\nVersion: 2.0\nDescription: A fixture')
else:
 assert '--force-yes' not in args and '--allow-unauthenticated' not in args
 assert 'APT::Get::AllowUnauthenticated=false' in args or 'APT::Get::AllowUnauthenticated=true' in args or args[-1]=='update'
 if args[-1]=='update': print('Indexes refreshed'); sys.exit(cfg.get('refresh_status',0))
 assert 'APT::Get::AutomaticRemove=false' in args and 'Dpkg::Options::=--force-confold' in args
 action=args[-2]; target=args[-1]
 if '--simulate' in args:
  if cfg.get('plan_failure'): print('Broken dependencies'); sys.exit(100)
  if cfg.get('essential_removal'): print('Remv core.system [1.0]')
  if action=='install':
   assert '--no-remove' in args
   print('Inst '+target.split('=')[0]+' [1.0] ('+cfg.get('candidate','2.0')+' Fixture [iphoneos-arm])')
   print('Conf dependency ('+cfg.get('dependency','1.0')+' Fixture [iphoneos-arm])')
  else: print('Remv '+target+' [1.0]')
 else:
  assert '--assume-yes' in args and ('=' in target or action=='remove')
  print('Configured fixture' if action=='install' else 'Removed fixture')
  sys.exit(100 if cfg.get('unsigned_repo') and 'APT::Get::AllowUnauthenticated=true' not in args else cfg.get('apply_status',0))
'''
        for name in ['apt-get', 'apt-cache']:
            path = fixture / 'usr/bin' / name
            path.write_text(fake); path.chmod(0o755)
        helper = fixture / 'helper'
        flags = shlex.split(subprocess.check_output(['gnustep-config', '--objc-flags'], text=True))
        libraries = shlex.split(subprocess.check_output(['gnustep-config', '--base-libs'], text=True))
        definitions = ['-DRC_PACKAGE_TEST=1', '-DRC_PKG_TEST_ROOT="'+str(fixture)+'"',
                       '-DRC_CALLER_UID='+str(os.getuid()), '-DRC_LOCK_OWNER='+str(os.getuid()),
                       *['-D'+name+'="'+str(fixture / relative)+'"' for name, relative in {
                           'RC_DOWNLOADS_DIR':'downloads', 'RC_STAGING_PARENT':'var/tmp', 'RC_DPKG_BINARY':'usr/bin/fake-dpkg',
                           'RC_LAUNCHCTL_BINARY':'usr/bin/fake-launchctl', 'RC_DPKG_LOCK':'var/lib/dpkg/lock',
                           'RC_OPERATION_LOCK':'var/tmp/receptor-packages.lock'}.items()]]
        subprocess.run(['gcc', *flags, '-std=gnu99', '-Wno-unused-function', '-Werror', *definitions,
                        str(ROOT/'Tools/receptor-package-helper.m'), '-o', str(helper), *libraries, '-lcrypto'], check=True)

        def run(*args):
            result = subprocess.run([str(helper), *args], capture_output=True, timeout=15,
                                    env={**os.environ, 'RC_INJECTED':'bad', 'DPKG_ROOT':'/not-allowed'})
            assert result.returncode == 0, (result.returncode, result.stdout.decode(errors='replace'), result.stderr.decode(errors='replace'))
            return plistlib.loads(result.stdout)

        def settings(**kwargs):
            config.write_text(json.dumps(kwargs))

        def apply_calls():
            return [a for binary,a in json.loads(record.read_text()) if binary=='apt-get' and '--assume-yes' in a]

        installed=run('installed')['items']
        assert installed[0]['Package']=='example.tweak' and installed[1]['protected']
        assert run('search','example')['items'][0]['Package']=='example.tweak'
        assert 'Version: 2.0' in run('details','example.tweak')['output']
        assert run('refresh')['status']==0
        plan=run('plan-install','example.tweak'); assert len(plan['token'])==64
        assert run('apply-install','example.tweak',plan['token'])['status']==0
        assert apply_calls()[-1][-1]=='example.tweak=2.0'
        remove=run('plan-remove','example.tweak')
        assert run('apply-remove','example.tweak',remove['token'])['status']==0
        print('PASS: actual helper installed/search/details/refresh and previewed exact-version install/remove via fake APT')
        count=len(apply_calls())
        assert 'error' in run('apply-install','example.tweak','0'*64)
        settings(dependency='2.0'); assert 'error' in run('apply-install','example.tweak',plan['token'])
        settings(); status.write_text(status.read_text()+'\n')
        assert 'error' in run('apply-install','example.tweak',plan['token'])
        for identifier in ['--force-all','../escape','..','.hidden','+foo','a*','foo;touch sentinel','example.tweak-','a/b','example.tweak=1']:
            assert 'error' in run('plan-install',identifier)
        assert 'error' in run('plan-remove','core.system')
        assert 'error' in run('plan-remove','cydia')
        settings(essential_removal=True); assert 'error' in run('plan-remove','example.tweak')
        settings(plan_failure=True); assert 'error' in run('plan-install','example.tweak')
        assert len(apply_calls())==count
        settings(apply_status=100); plan=run('plan-install','example.tweak')
        assert run('apply-install','example.tweak',plan['token'])['status']==100
        settings(refresh_status=100); assert run('refresh')['status']==100
        settings(unsigned_repo=True); plan=run('plan-install','example.tweak')
        assert run('apply-install','example.tweak',plan['token'])['status']==100
        assert run('apply-unsigned-install','example.tweak',plan['token'])['status']==0
        settings(); plan=run('plan-install','example.tweak')
        assert run('apply-install','example.tweak',plan['token'])['status']==0
        assert 'APT::Get::AllowUnauthenticated=false' in apply_calls()[-1]
        settings()
        print('PASS: changed dependency/state/token, dangerous identifiers, protected/transitive removals and native APT failures')
        assert run('last-result')['status']==0

        assert not run('sources')['items']
        uri='https://example.invalid/repo/'
        assert 'error' not in run('source-add',uri)
        managed=fixture/'etc/apt/sources.list.d/receptor.list'
        assert managed.read_text()=='deb '+uri+' ./\n'
        assert 'error' in run('source-add',uri)
        for bad in ['file:///etc/passwd','https://user:password@example.invalid/','https://example.invalid/\ndeb evil ./','https://example.invalid/#fragment','https://example.invalid/?x=1']:
            assert 'error' in run('source-add',bad)
        plan=run('plan-install','example.tweak')
        assert 'error' not in run('source-add','https://second.invalid/')
        assert 'error' in run('apply-install','example.tweak',plan['token'])
        source=next(s for s in run('sources')['items'] if s['name']==uri)
        assert 'error' not in run('source-remove',source['id']) and uri not in managed.read_text()
        assert 'error' in run('source-remove',source['id'])
        print('PASS: source add/duplicate/validation, stable source selection, removal, stale selection and source-bound plan tokens')

        cydia=fixture/'etc/apt/sources.list.d/cydia.list'
        cydia.write_text('deb https://cydia.invalid/ stable main\ndeb https://cydia.invalid/ testing main\ndeb https://keep.invalid/ ./\n')
        metadata=fixture/'var/lib/cydia/metadata.plist'
        original={'Sources':{'one':{'URI':'https://cydia.invalid/','Distribution':'stable'},'two':{'URI':'https://cydia.invalid/','Distribution':'testing'},'keep':{'URI':'https://keep.invalid/'}},'Packages':{'unrelated':'preserved'}}
        metadata.write_bytes(plistlib.dumps(original))
        source=next(s for s in run('sources')['items'] if s['name']=='https://cydia.invalid/')
        assert 'error' not in run('source-remove',source['id'])
        after=plistlib.loads(metadata.read_bytes()); assert list(after['Sources'])==['keep'] and after['Packages']==original['Packages']
        assert cydia.read_text()=='deb https://keep.invalid/ ./\n'
        backup=plistlib.loads((fixture/'var/lib/receptor/last-source-removal.plist').read_bytes())
        assert plistlib.loads(backup[str(metadata)])==original
        assert (fixture/'var/lib/receptor').stat().st_mode & 0o077==0
        metadata.write_bytes(b'not a property list'); before=cydia.read_bytes()
        source=next(s for s in run('sources')['items'] if s['name']=='https://keep.invalid/')
        assert 'error' in run('source-remove',source['id']) and cydia.read_bytes()==before
        metadata.write_bytes(plistlib.dumps({'Sources':{'keep':{'URI':'https://keep.invalid/'}}}))
        # Fail the second file update and verify the already-written source list rolls back.
        parent=metadata.parent; parent.chmod(0o500)
        try:
            assert 'error' in run('source-remove',source['id']) and cydia.read_bytes()==before
        finally:
            parent.chmod(0o700)
        preferences=fixture/'var/mobile/Library/Preferences/com.saurik.Cydia.plist'
        prefs={'CydiaSources':{'keep':{'URI':'https://keep.invalid/'}},'OtherPreference':'preserved'}
        preferences.write_bytes(plistlib.dumps(prefs)); metadata.unlink()
        assert 'error' not in run('source-remove',source['id'])
        assert plistlib.loads(preferences.read_bytes())=={'CydiaSources':{},'OtherPreference':'preserved'}
        print('PASS: Cydia multi-distribution metadata/source synchronization, unrelated metadata preservation, private backups and malformed-metadata refusal')
        with (fixture/'var/tmp/receptor-packages.lock').open('r+') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            assert 'error' in run('installed')
        managed.unlink(); managed.symlink_to(status)
        assert 'error' in run('sources')
        assert 'error' in run('unknown-operation')
        print('PASS: shared transaction lock, source symlink and unknown-operation rejection')
    print('Device-only caller authorization, Cydia process detection, UIKit and real legacy APT/TLS require device tests.')


if __name__ == '__main__':
    main()
