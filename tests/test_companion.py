#!/usr/bin/env python3
"""Exercise the actual Windows server, not a mock. Requires .NET Framework csc.

The iOS client still needs physical-device validation; this tests its wire protocol.
"""
from pathlib import Path
import hashlib
import hmac
import http.client
import os
import plistlib
import secrets
import socket
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def mac(key, text):
    return hmac.new(key.encode('ascii'), text.encode(), hashlib.sha256).hexdigest()


def main():
    compiler = Path(os.environ['WINDIR']) / 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    output = ROOT / 'build/desktop/CompanionTestHost.exe'
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(compiler), '/nologo', '/target:exe', '/warnaserror+',
                    '/reference:System.Security.dll', '/out:' + str(output), str(ROOT / 'tests/companion_host.cs'),
                    str(ROOT / 'Desktop/CompanionServer.cs'), str(ROOT / 'Desktop/ConnectionSettings.cs')], check=True)
    with tempfile.TemporaryDirectory(prefix='receptor-companion-test-') as temporary:
        source = Path(temporary) / 'Example & snowman \u2603.deb'
        payload = b'!<arch>\n' + secrets.token_bytes(256 * 1024)
        source.write_bytes(payload)
        settings = Path(temporary) / 'pairing.dat'
        def start():
            return subprocess.Popen([str(output), str(settings), str(source)], stdin=subprocess.PIPE,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        def pairing_info(port):
            connection = http.client.HTTPConnection('127.0.0.1', port, timeout=5)
            connection.request('GET', '/v2/pairing?nonce=' + secrets.token_hex(16))
            response = connection.getresponse()
            assert response.status == 200
            version, salt, session = response.read().decode('ascii').split('\n')
            connection.close()
            assert version == '2' and len(salt) == len(session) == 32
            return salt, session
        process = start()
        try:
            line = process.stdout.readline().strip().split()
            assert len(line) == 2, 'The test host did not report its endpoint.'
            port, code = int(line[0]), line[1]
            assert len(code) == 8 and set(code) <= set('ABCDEFGHJKLMNPQRSTUVWXYZ23456789')
            salt, session = pairing_info(port)
            key = hashlib.pbkdf2_hmac('sha256', code.encode(), bytes.fromhex(salt), 100000).hex()
            encrypted = settings.read_bytes()
            assert code.encode() not in encrypted and key.encode() not in encrypted

            def request(route='/v2/manifest', nonce=None, secret=None, method='GET', extra=None, server_session=None):
                nonce = nonce or secrets.token_hex(16)
                connection = http.client.HTTPConnection('127.0.0.1', port, timeout=5)
                headers = {'X-Receptor-Auth': mac(secret or key, 'GET\n' + route + '\n' + nonce + '\n' + (server_session or session))}
                headers.update(extra or {})
                connection.request(method, route + '?nonce=' + nonce, headers=headers)
                response = connection.getresponse()
                body, status, auth = response.read(), response.status, response.getheader('X-Receptor-Auth')
                connection.close()
                return status, body, auth, nonce

            status, body, auth, nonce = request()
            assert status == 200
            assert hmac.compare_digest(auth, mac(key, 'response\n' + nonce + '\n' + hashlib.sha256(body).hexdigest() + '\n' + session))
            manifest = plistlib.loads(body)
            assert manifest['protocol'] == 2 and len(manifest['files']) == 1
            file = manifest['files'][0]
            assert file['name'] == source.name and file['size'] == len(payload)
            assert file['sha256'] == hashlib.sha256(payload).hexdigest()
            print('PASS: authenticated plist manifest, Unicode names and file metadata')
            assert request(nonce=nonce)[0] == 409
            assert request(secret='0' * 64)[0] == 403
            assert request(method='POST')[0] == 403
            assert request(extra={'Content-Length': '1'})[0] == 403
            assert request('/../../Windows/win.ini')[0] == 403
            assert request('/v2/files/' + '0' * 32)[0] == 404
            assert request(server_session='0' * 32)[0] == 403
            print('PASS: replay, incorrect code, non-GET, body, traversal and unknown ID rejected')

            # Sharing is a snapshot, so a changed PC source never silently changes an offered DEB.
            source.write_bytes(b'!<arch>\nchanged')
            status, received, auth, nonce = request('/v2/files/' + file['id'])
            assert status == 200 and received == payload
            digest = hashlib.sha256(received).hexdigest()
            assert hmac.compare_digest(auth, mac(key, 'response\n' + nonce + '\n' + digest + '\n' + session))
            assert digest == file['sha256']
            tampered = received[:-1] + bytes([received[-1] ^ 1])
            assert not hmac.compare_digest(auth, mac(key, 'response\n' + nonce + '\n' + hashlib.sha256(tampered).hexdigest() + '\n' + session))
            assert not hmac.compare_digest(auth, mac(key, 'response\n' + secrets.token_hex(16) + '\n' + digest + '\n' + session))
            print('PASS: immutable streamed payload; tampering and substituted response nonce fail authentication')

            with socket.create_connection(('127.0.0.1', port), timeout=5) as raw:
                raw.sendall(b'GET /v2/manifest?nonce=' + secrets.token_hex(16).encode() + b' HTTP/1.1\r\nHost: test\r\nX-Receptor-Auth: a\r\nX-Receptor-Auth: b\r\n\r\n')
                try:
                    assert raw.recv(100) == b''
                except ConnectionResetError:
                    pass
            with socket.create_connection(('127.0.0.1', port), timeout=5) as raw:
                try:
                    raw.sendall(b'GET /' + b'A' * 9000 + b' HTTP/1.1\r\n\r\n')
                    assert raw.recv(100) == b''
                except ConnectionResetError:
                    pass
            assert request()[0] == 200
            print('PASS: duplicate/oversized headers rejected; server remains usable')
        finally:
            if process.poll() is None:
                process.communicate('\n', timeout=10)
            assert process.returncode == 0
        with socket.socket() as probe:
            assert probe.connect_ex(('127.0.0.1', port)) != 0
        print('PASS: stopping sharing closes the listener and revokes the session')
        previous_session, previous_salt = session, salt
        process = start()
        try:
            line = process.stdout.readline().strip().split()
            assert len(line) == 2 and line[1] == code
            port = int(line[0]); salt, session = pairing_info(port)
            assert salt == previous_salt and session != previous_session
            assert request(server_session=previous_session)[0] == 403
            assert request()[0] == 200
            print('PASS: encrypted saved identity/address restored; same pairing reconnects after restart; old-session authentication rejected')
        finally:
            if process.poll() is None: process.communicate('\n', timeout=10)
            assert process.returncode == 0
        settings.unlink()  # Equivalent to explicit desktop reset: generate a new identity.
        process = start()
        try:
            line = process.stdout.readline().strip().split()
            assert len(line) == 2
            port = int(line[0]); salt, session = pairing_info(port)
            assert salt != previous_salt and request()[0] == 403
            print('PASS: resetting desktop pairing rejects the old saved credential')
        finally:
            if process.poll() is None: process.communicate('\n', timeout=10)
            assert process.returncode == 0


if __name__ == '__main__':
    main()
