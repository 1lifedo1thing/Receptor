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
import io
import zipfile
import base64
import time

ROOT = Path(__file__).resolve().parents[1]


def mac(key, text):
    return hmac.new(key.encode('ascii'), text.encode(), hashlib.sha256).hexdigest()


def main():
    compiler = Path(os.environ['WINDIR']) / 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    output = ROOT / 'build/desktop/CompanionTestHost.exe'
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(compiler), '/nologo', '/target:exe', '/warnaserror+',
                    '/reference:System.Security.dll', '/out:' + str(output), str(ROOT / 'tests/companion_host.cs'),
                    str(ROOT / 'Desktop/CompanionServer.cs'), str(ROOT / 'Desktop/ConnectionSettings.cs'), str(ROOT / 'Desktop/RemoteProtocol.cs'), str(ROOT / 'Desktop/RemoteBroker.cs')], check=True)
    with tempfile.TemporaryDirectory(prefix='receptor-companion-test-') as temporary:
        source = Path(temporary) / 'Example & snowman \u2603.deb'
        payload = b'!<arch>\n' + secrets.token_bytes(256 * 1024)
        source.write_bytes(payload)
        zip_bytes = io.BytesIO()
        with zipfile.ZipFile(zip_bytes, 'w') as archive:
            archive.writestr('hello.txt', 'Receptor fixture')
        fixtures = {
            source.name: payload,
            'image.png': (ROOT / 'App/Resources/Icon.png').read_bytes(),
            'notes.txt': 'Hello, Receptor! \u2603\n'.encode(),
            'archive.zip': zip_bytes.getvalue(),
            'test.ipa': zip_bytes.getvalue(),  # Transport fixture, not an installable application.
            'README': b'No extension is required.',
            'empty-file': b'',
            'empty.txt': b'',
            'unknown.extension': b'\x00\xff\x01arbitrary data',
        }
        sources = []
        for name, data in fixtures.items():
            file_path = Path(temporary) / name
            file_path.write_bytes(data); sources.append(str(file_path))
        settings = Path(temporary) / 'pairing.dat'
        def start(disabled=False):
            env = dict(os.environ, RECEPTOR_TEST_RECEIVING_DISABLED='1' if disabled else '0')
            return subprocess.Popen([str(output), str(settings)] + sources, stdin=subprocess.PIPE,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
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
            assert manifest['accepts_uploads'] is True
            assert manifest['protocol'] == 2 and len(manifest['files']) == len(fixtures)
            assert len({f['id'] for f in manifest['files']}) == len(fixtures)
            file = next(f for f in manifest['files'] if f['name'] == source.name)
            assert file['name'] == source.name and file['size'] == len(payload)
            assert file['sha256'] == hashlib.sha256(payload).hexdigest()
            print('PASS: authenticated plist manifest, Unicode names and file metadata')
            for item in manifest['files']:
                status, received, auth, transfer_nonce = request('/v2/files/' + item['id'])
                expected = fixtures[item['name']]
                digest = hashlib.sha256(expected).hexdigest()
                assert status == 200 and received == expected and item['size'] == len(expected)
                assert item['sha256'] == digest
                assert hmac.compare_digest(auth, mac(key, 'response\n' + transfer_nonce + '\n' + digest + '\n' + session))
            print('PASS: PNG, UTF-8 text, ZIP, IPA, DEB, arbitrary binary, extensionless and zero-byte files preserve bytes and authenticate')
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

            receive_folder = Path(temporary) / 'received'

            def upload(data=b'', name='from-device.bin', nonce=None, digest=None, encoded=None, secret=None, length=None, extra=None, server_session=None):
                nonce = nonce or secrets.token_hex(16)
                digest = digest or hashlib.sha256(data).hexdigest()
                encoded = encoded or base64.b64encode(name.encode()).decode()
                length = str(len(data)) if length is None else length
                headers = {'Content-Length': length, 'X-Receptor-SHA256': digest, 'X-Receptor-Name': encoded,
                           'X-Receptor-Auth': mac(secret or key, 'PUT\n/v2/uploads\n' + nonce + '\n' + (server_session or session) + '\n' + length + '\n' + digest + '\n' + encoded)}
                headers.update(extra or {})
                connection = http.client.HTTPConnection('127.0.0.1', port, timeout=5)
                connection.request('PUT', '/v2/uploads?nonce=' + nonce, body=data, headers=headers)
                response = connection.getresponse()
                status, body, auth = response.status, response.read(), response.getheader('X-Receptor-Auth')
                connection.close()
                return status, body, auth, nonce

            process.stdin.write('receive-off\n'); process.stdin.flush()
            assert process.stdout.readline().strip() == 'updated'
            assert plistlib.loads(request()[1])['accepts_uploads'] is False
            assert upload(name='disabled-live')[0] == 403
            process.stdin.write('receive-on\n'); process.stdin.flush()
            assert process.stdout.readline().strip() == 'updated'
            assert pairing_info(port) == (salt, session)
            assert plistlib.loads(request()[1])['accepts_uploads'] is True
            print('PASS: receiving toggles while sharing stays active; saved pairing, server session and file list survive')
            incoming = b'\x00\xff' + secrets.token_bytes(512 * 1024)
            status, body, auth, upload_nonce = upload(incoming, 'iPad snowman \u2603.bin')
            assert status == 201 and body.decode() == 'iPad snowman \u2603.bin'
            assert (receive_folder / body.decode()).read_bytes() == incoming
            assert hmac.compare_digest(auth, mac(key, 'response\n' + upload_nonce + '\n' + hashlib.sha256(body).hexdigest() + '\n' + session))
            # Empty replay body avoids platform-dependent TCP reset on unread rejected data.
            assert upload(name='iPad snowman \u2603.bin', nonce=upload_nonce)[0] == 409
            status, body, _, _ = upload(b'duplicate', 'iPad snowman \u2603.bin')
            assert status == 201 and body.decode() == 'iPad snowman \u2603 (1).bin'
            assert (receive_folder / 'iPad snowman \u2603.bin').read_bytes() == incoming
            assert (receive_folder / body.decode()).read_bytes() == b'duplicate'
            status, body, _, _ = upload(name='empty')
            assert status == 201 and (receive_folder / body.decode()).read_bytes() == b''
            for name, expected in [('CON.txt', '_CON.txt'), ('a:b?.txt', 'a_b_.txt'), (' padded. ', 'padded')]:
                status, body, _, _ = upload(b'safe', name)
                assert status == 201 and body.decode() == expected
                assert (receive_folder / expected).read_bytes() == b'safe'
            print('PASS: device uploads preserve binary/Unicode/empty files, authenticate receipts, sanitize Windows names and never overwrite')

            assert upload(secret='0' * 64)[0] == 403
            assert upload(b'bad', digest='0' * 64)[0] == 422
            assert upload(length='2147483648')[0] == 403
            assert upload(length='00')[0] == 403
            assert upload(extra={'Transfer-Encoding': 'chunked'})[0] == 403
            assert upload(extra={'X-Receptor-Name': base64.b64encode(b'tampered').decode()})[0] == 403
            assert upload(server_session='0' * 32)[0] == 403
            for name in ['../escape.txt', 'a/b', 'a\\b', '.', '..', 'bad\x01name']:
                assert upload(name=name)[0] == 400
            assert upload(encoded='/w==')[0] == 400  # Invalid UTF-8.
            assert len(list(receive_folder.iterdir())) == 6
            assert not (Path(temporary) / 'escape.txt').exists()
            print('PASS: upload authentication, replay, session, traversal, invalid UTF-8, metadata tampering, length and SHA-256 failures rejected')

            # An authenticated but truncated sender must leave neither a published file nor a partial.
            nonce = secrets.token_hex(16); encoded = base64.b64encode(b'aborted.bin').decode()
            digest = hashlib.sha256(b'x' * 10000).hexdigest()
            auth = mac(key, 'PUT\n/v2/uploads\n' + nonce + '\n' + session + '\n10000\n' + digest + '\n' + encoded)
            with socket.create_connection(('127.0.0.1', port), timeout=5) as raw:
                raw.sendall(('PUT /v2/uploads?nonce=' + nonce + ' HTTP/1.1\r\nHost: test\r\nContent-Length: 10000\r\nX-Receptor-Name: ' + encoded + '\r\nX-Receptor-SHA256: ' + digest + '\r\nX-Receptor-Auth: ' + auth + '\r\n\r\n').encode() + b'x')
                # Wait for the first request to own the inbound slot before testing contention.
                deadline = time.monotonic() + 5
                while not list(receive_folder.glob('*.part')) and time.monotonic() < deadline:
                    time.sleep(.02)
                assert list(receive_folder.glob('*.part'))
                assert upload(name='busy.bin')[0] == 409
            deadline = time.monotonic() + 5
            while list(receive_folder.glob('*.part')) and time.monotonic() < deadline:
                time.sleep(.02)
            assert not list(receive_folder.glob('*.part')) and not (receive_folder / 'aborted.bin').exists()
            for i in range(26):
                assert upload(name='limit-%d' % i)[0] == 201
            assert upload(name='over-limit')[0] == 429
            assert request()[0] == 200
            print('PASS: interrupted upload cleanup, one inbound transfer at a time and 32-file session limit')
            saved_receive = Path(str(settings) + '.receive').read_bytes()
            assert str(receive_folder).encode() not in saved_receive
            print('PASS: receive preferences encrypted independently of the backwards-compatible pairing file')
        finally:
            if process.poll() is None:
                process.communicate('\n', timeout=10)
            assert process.returncode == 0
        with socket.socket() as probe:
            assert probe.connect_ex(('127.0.0.1', port)) != 0
        print('PASS: stopping sharing closes the listener and revokes the session')
        previous_session, previous_salt = session, salt
        process = start(disabled=True)
        try:
            line = process.stdout.readline().strip().split()
            assert len(line) == 2 and line[1] == code
            port = int(line[0]); salt, session = pairing_info(port)
            assert salt == previous_salt and session != previous_session
            assert request(server_session=previous_session)[0] == 403
            assert request()[0] == 200
            assert plistlib.loads(request()[1])['accepts_uploads'] is False
            assert upload(name='disabled')[0] == 403
            print('PASS: disabled receiving is advertised and rejects uploads')
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
            new_key = hashlib.pbkdf2_hmac('sha256', line[1].encode(), bytes.fromhex(salt), 100000).hex()
            nonce = secrets.token_hex(16); encoded = base64.b64encode(b'stop-during-upload').decode()
            digest = hashlib.sha256(b'x' * 10000).hexdigest()
            auth = mac(new_key, 'PUT\n/v2/uploads\n' + nonce + '\n' + session + '\n10000\n' + digest + '\n' + encoded)
            with socket.create_connection(('127.0.0.1', port), timeout=5) as raw:
                raw.sendall(('PUT /v2/uploads?nonce=' + nonce + ' HTTP/1.1\r\nHost: test\r\nContent-Length: 10000\r\nX-Receptor-Name: ' + encoded + '\r\nX-Receptor-SHA256: ' + digest + '\r\nX-Receptor-Auth: ' + auth + '\r\n\r\n').encode() + b'x')
                deadline = time.monotonic() + 5
                while not list(receive_folder.glob('*.part')) and time.monotonic() < deadline:
                    time.sleep(.02)
                assert list(receive_folder.glob('*.part'))
                process.communicate('\n', timeout=10)
            assert not list(receive_folder.glob('*.part')) and not (receive_folder / 'stop-during-upload').exists()
            print('PASS: stopping the server during an active upload closes the connection and removes incomplete data')
        finally:
            if process.poll() is None: process.communicate('\n', timeout=10)
            assert process.returncode == 0


if __name__ == '__main__':
    main()
