#!/usr/bin/env python3
"""Controlled HTTP fixtures for testing Receptor on a device. Python 3 standard library only."""

import argparse
import io
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import time
from urllib.parse import urlsplit
import zipfile


def archive_bytes():
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("hello.txt", "Downloaded by Receptor.\n")
    return output.getvalue()


ARCHIVE = archive_bytes()
INDEX = b"""<!doctype html><html><head><meta name="viewport" content="width=device-width"></head>
<body><h1>Receptor device fixtures</h1><ul>
<li><a href="/archive.zip">ZIP: navigation policy</a></li>
<li><a href="/raw.txt">Plain text: download instead of render</a></li>
<li><a href="/attachment">Attachment without extension</a></li>
<li><a href="/unknown">Unsupported MIME without extension</a></li>
<li><a href="/redirect">Redirect to attachment</a></li>
<li><a href="/archive.zip" target="_blank">New-window ZIP</a></li>
<li><a href="/slow.zip">Slow 8 MiB transfer: progress, cancel, background expiry</a></li>
<li><a href="/error.zip">HTTP error: must not create a saved file</a></li>
<li><a href="/truncated.zip">Truncated response: must fail</a></li>
<li><a href="/unsafe">Unsafe attachment filename: must stay in Receptor directory</a></li>
<li><a href="/set-cookie">Set cookie, then download protected ZIP</a></li>
</ul><p>Repeat a successful link to check duplicate filenames.</p></body></html>"""


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def reply(self, status, body, mime="text/html", headers=()):
        self.send_response(status)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for key, value in headers:
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlsplit(self.path).path
        try:
            if path == "/":
                self.reply(200, INDEX)
            elif path == "/archive.zip":
                self.reply(200, ARCHIVE, "application/zip")
            elif path == "/raw.txt":
                self.reply(200, b"Receptor plain-text fixture.\n", "text/plain")
            elif path in ("/attachment", "/unsafe"):
                filename = "example.zip" if path == "/attachment" else "../../escaped.zip"
                self.reply(200, ARCHIVE, "application/octet-stream",
                           [("Content-Disposition", 'attachment; filename="' + filename + '"')])
            elif path == "/unknown":
                self.reply(200, b"Receptor unknown MIME fixture.\n", "application/x-receptor-test")
            elif path == "/redirect":
                self.reply(302, b"", headers=[("Location", "/attachment")])
            elif path == "/error.zip":
                self.reply(503, b"Intentional server failure.\n", "text/plain")
            elif path == "/truncated.zip":
                self.send_response(200)
                self.send_header("Content-Type", "application/zip")
                self.send_header("Content-Length", "1048576")
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(ARCHIVE)
                self.wfile.flush()
                self.close_connection = True
            elif path == "/slow.zip":
                # Bytes, not a valid ZIP. Useful for progress/cancellation, not preview.
                chunk = b"R" * 16384
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Length", str(len(chunk) * 512))
                self.end_headers()
                for _ in range(512):
                    self.wfile.write(chunk)
                    self.wfile.flush()
                    time.sleep(1)
            elif path == "/set-cookie":
                self.reply(200, b'<a href="/protected.zip">Download protected ZIP</a>',
                           headers=[("Set-Cookie", "receptor_fixture=allowed; Path=/; HttpOnly")])
            elif path == "/protected.zip":
                if "receptor_fixture=allowed" in self.headers.get("Cookie", ""):
                    self.reply(200, ARCHIVE, "application/zip")
                else:
                    self.reply(403, b"Cookie missing.\n", "text/plain")
            else:
                self.reply(404, b"Unknown fixture.\n", "text/plain")
        except (BrokenPipeError, ConnectionResetError):
            pass  # A device cancelling a download is expected.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.bind, args.port), Handler)
    print("Receptor fixtures: http://%s:%d/" % server.server_address, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
