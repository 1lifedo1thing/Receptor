#!/usr/bin/env python3
"""GNUstep/native agent + actual C# broker over loopback; fake device helpers only."""
import base64
import hashlib
import http.client
import json
import os
from pathlib import Path
import plistlib
import shlex
import signal
import subprocess
import tempfile
import threading
import time

ROOT=Path(__file__).resolve().parents[1]


def main():
    flags=shlex.split(subprocess.check_output(['gnustep-config','--objc-flags'],text=True))
    libs=shlex.split(subprocess.check_output(['gnustep-config','--base-libs'],text=True))
    with tempfile.TemporaryDirectory(prefix='receptor-remote-test-') as temp:
        fixture=Path(temp)
        for name in ['var/lib/receptor','var/tmp','usr/libexec','downloads']:
            (fixture/name).mkdir(parents=True,exist_ok=True)
        (fixture/'var/lib/receptor').chmod(0o700)
        common=['gcc',*flags,'-std=gnu99','-Werror','-Wno-unused-function','-DRC_REMOTE_HOST_TEST=1',f'-DRC_REMOTE_TEST_ROOT="{fixture}"']
        def build(output,sources,extra=(),curl=False):
            subprocess.run([*common,*extra,*[str(ROOT/source) for source in sources],'-o',str(output),*libs,'-lcrypto',*(['-lcurl'] if curl else [])],check=True)
        probe=fixture/'crypto-probe'
        build(probe,['tests/remote_crypto_probe.m','RCRemoteCrypto.m'])
        file_helper=fixture/'usr/libexec/receptor-file-helper'
        build(file_helper,['Tools/receptor-file-helper.m','RCRemoteCrypto.m'],[f'-DRC_FILE_TEST_UID={os.getuid()}',f'-DRC_FILE_TEST_DIRECTORY="{fixture / "downloads"}"'])
        agent_path=fixture/'usr/libexec/receptor-remote-agent'
        build(agent_path,['Tools/receptor-remote-agent.m','RCRemoteCrypto.m','RCRemoteSupport.m'],curl=True)
        package=fixture/'usr/libexec/receptor-package-helper'
        package.write_text('#!/usr/bin/python3 -I\n'+f'ROOT={str(fixture)!r}\n'+r'''
import json,pathlib,plistlib,sys,time
root=pathlib.Path(ROOT); record=root/'calls.json'; calls=json.loads(record.read_text()) if record.exists() else []; calls.append(sys.argv[1:]); record.write_text(json.dumps(calls))
op=sys.argv[1]
if op=='installed': result={'items':[{'Package':'example.tweak','Version':'1.0','Description':'Fixture'}]}
elif op=='plan-install': result={'output':'Inst example.tweak (2.0 Fixture)','token':'1'*64}
elif op=='apply-install':
 time.sleep(.7 if (root/'slow').exists() else 0); (root/'applied').write_text('done'); result={'output':'Configured fixture','status':0}
elif op=='last-result': result={'output':'Fixture package log','status':0}
elif op=='sources': result={'items':[]}
else: result={'error':'Unsupported fake package operation'}
sys.stdout.buffer.write(plistlib.dumps(result))
''')
        package.chmod(0o755)
        host=subprocess.Popen(['mono',str(ROOT/'build/desktop/RemoteTestHost.exe')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        line=host.stdout.readline().strip()
        assert line,host.stderr.read()
        bootstrap=plistlib.loads(base64.b64decode(line))
        def rpc(value):
            host.stdin.write(base64.b64encode(plistlib.dumps(value)).decode()+'\n');host.stdin.flush()
            line=host.stdout.readline().strip();assert line,'Remote test host exited'
            return plistlib.loads(base64.b64decode(line))
        def crypto(value):
            result=subprocess.run([str(probe)],input=plistlib.dumps(value),capture_output=True,timeout=10)
            assert result.returncode==0,result.stderr.decode(errors='replace')
            value=plistlib.loads(result.stdout);assert 'error' not in value,value
            return value
        seed=os.urandom(32)
        enrollment=crypto({'action':'seal','seed':seed,'publicKey':bootstrap['publicKey'],'pairingKey':bootstrap['pairingKey']})
        device=enrollment['device']; assert device==hashlib.sha256(seed).hexdigest()[:32]
        assert enrollment['fingerprint']==bootstrap['fingerprint']
        assert rpc({'action':'unseal','data':enrollment['sealed']})['seed']==seed
        for plain in [b'',b'hello',os.urandom(65537)]:
            nonce=os.urandom(16).hex()
            native=crypto({'action':'encrypt','seed':seed,'plain':plain,'device':device,'nonce':nonce,'direction':'request'})
            assert rpc({'action':'decrypt','seed':seed,'frame':native['frame']})['plain']==plain
            managed=rpc({'action':'encrypt','seed':seed,'plain':plain,'device':device,'nonce':nonce})
            assert crypto({'action':'decrypt','seed':seed,'frame':managed['frame']})['plain']==plain
            assert crypto({'action':'mac','seed':seed,'frame':managed['frame'],'device':device,'nonce':nonce,'direction':'response'})['auth']==managed['auth']
        assert 'error' in rpc({'action':'parse','data':b'<!DOCTYPE plist [<!ENTITY x SYSTEM "file:///etc/passwd">]><plist><dict><key>x</key><string>&x;</string></dict></plist>'})
        print('PASS: native/.NET RSA-OAEP enrollment, pinned key fingerprint, AES-CBC/HMAC vectors including empty/binary data, and XML external-entity refusal')
        config={'host':f'127.0.0.1:{bootstrap["port"]}','seed':seed,'sealed':enrollment['sealed'],'enrollment':enrollment['enrollment'],'device':device,'publicKey':bootstrap['publicKey']}
        config_path=fixture/'var/lib/receptor/remote.plist'
        def save_config(): config_path.write_bytes(plistlib.dumps(config));config_path.chmod(0o600)
        save_config()
        def direct(message,nonce=None,mutate=False):
            nonce=nonce or os.urandom(16).hex()
            encoded=crypto({'action':'encrypt','seed':seed,'plain':plistlib.dumps(message),'device':device,'nonce':nonce,'direction':'request'})
            body=encoded['frame'];auth=encoded['auth']
            if mutate: body=body[:-1]+bytes([body[-1]^1])
            connection=http.client.HTTPConnection('127.0.0.1',bootstrap['port'],timeout=15)
            connection.request('POST','/v3/control',body=body,headers={'X-RC-Device':device,'X-RC-Nonce':nonce,'X-RC-Sealed':base64.b64encode(config['sealed']).decode(),'X-RC-Enrollment':config['enrollment'],'X-RC-Auth':auth})
            response=connection.getresponse();data=response.read();status=response.status;response_auth=response.getheader('X-Receptor-Auth');connection.close()
            if status!=200:return status,None
            assert crypto({'action':'mac','seed':seed,'frame':data,'device':device,'nonce':nonce,'direction':'response'})['auth']==response_auth
            return status,plistlib.loads(crypto({'action':'decrypt','seed':seed,'frame':data})['plain'])
        assert direct({'session':'','counter':0},mutate=True)[0]==403
        status,challenge=direct({'session':'','counter':0});assert status==200
        assert direct({'session':challenge['session'],'counter':1})[0]==200
        assert direct({'session':challenge['session'],'counter':1})[0]==403
        print('PASS: actual HTTP v3 encrypted exchange, tamper authentication and monotonic-counter replay rejection')
        agent=None
        def start_agent():return subprocess.Popen([str(agent_path)],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        def query(request,timeout=15):return rpc({'action':'request','device':device,'request':request,'timeout':timeout})
        def pkg(*args):return {'op':'packages','args':list(args)}
        def files(action,**values):return {'op':'files','action':action,**values}
        try:
            # A queued timeout must not later run; a dispatched timeout must not
            # be redelivered, and mutations require a read-only recovery query.
            cancelled=query(pkg('apply-install','example.tweak','1'*64),1)
            assert 'cancelled before dispatch' in cancelled.get('error','')
            assert 'command' not in direct({'session':challenge['session'],'counter':2})[1]
            expired={}
            waiter=threading.Thread(target=lambda:expired.update(query(pkg('apply-install','example.tweak','1'*64),1)))
            waiter.start();time.sleep(.1)
            dispatched=direct({'session':challenge['session'],'counter':3})[1]
            assert 'command' in dispatched
            waiter.join(timeout=3);assert not waiter.is_alive() and 'may still be running' in expired.get('error','')
            assert 'command' not in direct({'session':challenge['session'],'counter':4})[1]
            assert 'uncertain outcome' in query(pkg('apply-install','example.tweak','1'*64),1).get('error','')
            print('PASS: queued expiry cancels dispatch; dispatched expiry is not redelivered and requires a read-only recovery query')
            agent=start_agent();time.sleep(.3)
            initial=query(pkg('installed'))
            if 'items' not in initial:
                agent.kill();agent.wait(timeout=5)
                raise AssertionError((initial,agent.stderr.read().decode()[-2000:]))
            assert initial['items'][0]['Package']=='example.tweak'
            plan=query(pkg('plan-install','example.tweak'));assert len(plan['token'])==64
            assert query(pkg('apply-install','example.tweak',plan['token']))['status']==0
            assert 'error' in query(pkg('remote-enable','anything'))
            assert 'error' in query(pkg('remote-start'))
            assert 'error' in query({'op':'shell','command':'touch SENTINEL'})
            print('PASS: real native agent polls the actual desktop broker, runs only fixed helpers and reports package previews/results without a foreground app')
            payload=os.urandom(190000);name='snowman \u2603.bin'
            start=query(files('write-start',name=name,size=len(payload),sha256=hashlib.sha256(payload).hexdigest()));upload=start['id']
            offset=0
            while offset<len(payload):
                chunk=payload[offset:offset+65536];reply=query(files('write-chunk',id=upload,offset=offset,data=chunk));offset+=len(chunk);assert reply['offset']==offset
            assert query(files('write-finish',id=upload))['saved']==name
            duplicate=query(files('write-start',name=name,size=0,sha256=hashlib.sha256(b'').hexdigest()))
            assert query(files('write-finish',id=duplicate['id']))['saved']=='snowman \u2603 (1).bin'
            listing=query(files('list'))['items'];assert len(listing)==2
            info=query(files('info',name=name));assert info['sha256']==hashlib.sha256(payload).hexdigest()
            output=bytearray()
            while len(output)<info['size']:
                reply=query(files('read',name=name,token=info['token'],offset=len(output),length=65536));output.extend(reply['data'])
            assert bytes(output)==payload
            for bad in ['../outside','.receptor-remote-upload.plist','a/b','a\\b']:
                assert 'error' in query(files('info',name=bad))
            outside=fixture/'outside';outside.write_bytes(b'private');(fixture/'downloads/link').symlink_to(outside)
            assert 'error' in query(files('info',name='link'))
            (fixture/'downloads'/name).write_bytes(b'changed')
            assert 'error' in query(files('read',name=name,token=info['token'],offset=0,length=10))
            print('PASS: unattended encrypted binary/Unicode/empty uploads/downloads, no overwrite, source-change checks, hidden files, traversal and symlink boundaries')
            assert rpc({'action':'restart'})['ok'];time.sleep(3)
            assert query(pkg('installed'),20)['items']
            agent.kill();agent.wait(timeout=5);agent=start_agent();time.sleep(.4)
            assert query(pkg('installed'),20)['items']
            print('PASS: saved identity reconnects after PC/server and native-agent restarts without interactive device setup')
            # Kill only the agent after it durably records and starts a fake mutation.
            (fixture/'slow').write_text('yes');result={}
            thread=threading.Thread(target=lambda:result.update(query(pkg('apply-install','example.tweak','1'*64),20)));thread.start()
            deadline=time.monotonic()+10;last=fixture/'var/lib/receptor/remote-last-job.plist'
            before=sum(c[0]=='apply-install' for c in json.loads((fixture/'calls.json').read_text()))
            while time.monotonic()<deadline:
                if last.exists():
                    value=plistlib.loads(last.read_bytes())
                    calls=json.loads((fixture/'calls.json').read_text())
                    if 'body' not in value and sum(c[0]=='apply-install' for c in calls)>before:break
                time.sleep(.01)
            else:raise AssertionError('Fake mutation did not start')
            agent.kill();agent.wait(timeout=5);agent=start_agent();thread.join(timeout=25);assert not thread.is_alive()
            assert 'uncertain' in result.get('error','').lower()
            time.sleep(1);calls=json.loads((fixture/'calls.json').read_text());assert sum(c[0]=='apply-install' for c in calls)==before+1
            print('PASS: interrupted dispatched mutation is reported uncertain and is never automatically executed twice')
            assert rpc({'action':'off'})['ok']
            status_path=fixture/'var/lib/receptor/remote-status.plist';deadline=time.monotonic()+10
            while time.monotonic()<deadline:
                if status_path.exists() and 'PC rejected background access' in plistlib.loads(status_path.read_bytes()).get('message',''):break
                time.sleep(.1)
            else:raise AssertionError('Disabled-PC rejection was not reported in device diagnostics')
            assert rpc({'action':'on'})['ok'];time.sleep(3)
            assert query(pkg('installed'),20)['items']
            print('PASS: device diagnostics distinguish a PC rejection and saved access reconnects when desktop access is re-enabled')
            config_path.unlink();agent.wait(timeout=8)
            count=len(json.loads((fixture/'calls.json').read_text()))
            assert 'error' in query(pkg('installed'),2)
            time.sleep(.2);assert len(json.loads((fixture/'calls.json').read_text()))==count
            print('PASS: revoking the local background grant stops the agent and prevents further device operations')
        finally:
            if agent is not None and agent.poll() is None:
                agent.terminate()
                try:agent.wait(timeout=28)
                except subprocess.TimeoutExpired:agent.kill();agent.wait(timeout=5)
            try:rpc({'action':'exit'})
            finally:
                host.communicate(timeout=10)
        print('These tests do not execute real device package managers, launchd jobs, resprings or mobile-user privilege changes.')


if __name__=='__main__':main()
