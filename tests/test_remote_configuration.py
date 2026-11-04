#!/usr/bin/env python3
"""Production setup/service validation under GNUstep; fake launchctl only."""
import fcntl
import datetime
import json
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
        launchctl=base/'fake-launchctl'
        launchctl.write_text('#!/usr/bin/python3 -I\n'+f'ROOT={str(base)!r}\n'+r'''
import json,pathlib,plistlib,sys
root=pathlib.Path(ROOT);op=sys.argv[1];calls=root/'launch-calls.json';values=json.loads(calls.read_text()) if calls.exists() else [];values.append(sys.argv[1:]);calls.write_text(json.dumps(values))
if op=='list':
 if (root/'no-list').exists():sys.exit(7)
 if '-x' in sys.argv and (root/'no-xml').exists():sys.exit(2)
 if len(sys.argv)>2 and (root/'table-only').exists():sys.exit(2)
 if not (root/'loaded').exists():sys.exit(113)
 result={'Label':'com.receptor.remote','LastExitStatus':2 if (root/'failed').exists() else 0}
 if (root/'running').exists():result['PID']=12345
 if len(sys.argv)==2:print('PID\tStatus\tLabel\n999\t0\tother.job\n'+str(result.get('PID','-'))+'\t'+str(result['LastExitStatus'])+'\tcom.receptor.remote')
 elif '-x' not in sys.argv:
  print('{\n "Label" = "com.receptor.remote";\n "LastExitStatus" = '+str(result['LastExitStatus'])+';')
  if 'PID' in result:print(' "PID" = '+str(result['PID'])+';')
  print('};')
 else:sys.stdout.buffer.write(plistlib.dumps(result))
elif op=='load':
 if (root/'load-failure').exists():sys.exit(5)
 (root/'loaded').write_text('yes')
elif op=='start':
 if (root/'start-failure').exists():sys.exit(5)
 (root/'running').write_text('yes')
else:sys.exit(2)
''');launchctl.chmod(0o755)
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
        assert status['serviceLoaded'] and status['serviceRunning']
        calls=json.loads((base/'launch-calls.json').read_text())
        assert ['load','-w','/Library/LaunchDaemons/com.receptor.remote.plist'] in calls and ['start','com.receptor.remote'] in calls
        assert all(field not in status for field in ['seed','sealed','enrollment','publicKey'])
        print('PASS: explicit setup saves a private per-device secret, removes staged credentials and exposes only redacted background status')
        # Startup failures must not pretend that a saved grant is a connection.
        (base/'running').unlink();(base/'loaded').unlink();(base/'load-failure').write_text('yes')
        assert 'load failed (launchctl 5' in run('remote-start')['error']
        assert run('remote-status')['serviceLoaded'] is False
        (base/'load-failure').unlink();(base/'start-failure').write_text('yes')
        assert 'start failed (launchctl 5' in run('remote-start')['error']
        (base/'start-failure').unlink();assert run('remote-start')['enabled']
        assert run('remote-status')['serviceRunning']
        (base/'running').unlink();(base/'failed').write_text('yes')
        assert 'last exit 2' in run('remote-status')['output']
        (base/'failed').unlink();assert run('remote-start')['enabled']
        # Starting an already running service must never stop or start it again.
        count=len(json.loads((base/'launch-calls.json').read_text()))
        assert run('remote-start')['enabled']
        assert json.loads((base/'launch-calls.json').read_text())[count:]==[['list','-x','com.receptor.remote']]
        (base/'no-xml').write_text('yes');assert run('remote-status')['serviceRunning']
        (base/'running').unlink();(base/'failed').write_text('yes')
        assert 'last exit 2' in run('remote-status')['output']
        assert run('remote-start')['serviceRunning']
        (base/'table-only').write_text('yes');assert run('remote-status')['serviceRunning']
        (base/'running').unlink();assert 'last exit 2' in run('remote-status')['output']
        assert run('remote-start')['serviceRunning']
        (base/'no-list').write_text('yes')
        unknown=run('remote-start');assert unknown['enabled'] and not unknown['serviceStatusKnown'] and 'error' not in unknown
        assert 'could not verify' in run('remote-status')['output']
        (base/'no-list').unlink();(base/'table-only').unlink();(base/'no-xml').unlink();(base/'failed').unlink()
        print('PASS: unsupported XML/single-job queries fall back to legacy dictionaries/tables; successful load/start with unavailable listing is not a launchctl 0 failure')
        heartbeat=base/'var/lib/receptor/remote-status.plist'
        def report(date,device=saved['device']):
            heartbeat.write_bytes(plistlib.dumps({'device':device,'updated':date,'message':'Fixture connection error'}));heartbeat.chmod(0o600)
        report(datetime.datetime.now(datetime.timezone.utc));assert run('remote-status')['output']=='Fixture connection error'
        report(datetime.datetime(2000,1,1));assert run('remote-status')['output']!='Fixture connection error'
        report(datetime.datetime.now(datetime.timezone.utc),'0'*32);assert run('remote-status')['output']!='Fixture connection error'
        print('PASS: fixed launchctl load/start, visible startup failures, safe retry without restarting a running service, and fresh matching-device diagnostics')
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
