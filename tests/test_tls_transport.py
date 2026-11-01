#!/usr/bin/env python3
"""Integration tests for the pinned curl/Mbed TLS transport (native Linux probe)."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import ssl
import os
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parent.parent
PROBE = ROOT / "build/tls-probe"
CA = ROOT / "layout/Library/Application Support/Receptor/cacert.pem"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/requires-user-agent" and self.headers.get('User-Agent') != 'Receptor/1.4.1 (iOS)':
            self.close_connection = True
            return  # Some hosts close anonymous-client connections without an HTTP response.
        payload = b"Receptor TLS 1.2 fixture\n"
        if self.path == "/redirect":
            self.send_response(302)
            self.send_header("Location", "/payload.ipa")
            payload = b""
        else:
            self.send_response(200)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *args):
        pass


def probe(url, roots, expected, concurrent=False, no_agent=False):
    command = [str(PROBE), url, str(roots)] + (["3"] if concurrent else [])
    environment = os.environ.copy()
    if no_agent: environment['RC_PROBE_NO_USER_AGENT'] = '1'
    else: environment.pop('RC_PROBE_NO_USER_AGENT', None)
    result = subprocess.run(command, capture_output=True, text=True, timeout=55, env=environment)
    print(result.stdout.strip())
    assert result.returncode in (expected if isinstance(expected, tuple) else (expected,)), (url, result.returncode, result.stderr)


def main():
    assert PROBE.exists(), "Run bash scripts/build-host-tls-probe.sh first"
    with tempfile.TemporaryDirectory(prefix="receptor-tls-test-") as directory:
        path = Path(directory)
        cert, key = path / "cert.pem", path / "key.pem"
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                        "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost",
                        "-keyout", str(key), "-out", str(cert)], check=True, capture_output=True)
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.maximum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(cert, key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base = "https://localhost:%d" % server.server_port
            probe(base + "/payload.ipa", cert, 0)
            probe(base + "/redirect", cert, 0)
            probe(base + "/payload.ipa", cert, 0, concurrent=True)
            probe(base + "/requires-user-agent", cert, 0)
            probe(base + "/requires-user-agent", cert, (52, 56), no_agent=True)
            probe(base + "/payload.ipa", CA, 60)  # Untrusted issuer must fail.
            probe("https://127.0.0.1:%d/payload.ipa" % server.server_port, cert, 60)  # Wrong hostname must fail.
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)
    print("PASS: TLS 1.2 body download, HTTPS redirect, concurrent transfers, User-Agent-required host, untrusted issuer and wrong-host rejection")
    print("This validates the portable TLS stack, not UIKit or the physical iOS runtime.")


if __name__ == "__main__":
    main()
