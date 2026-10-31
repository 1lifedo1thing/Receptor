#!/usr/bin/env python3
"""Check packaging inputs and fixture HTTP responses without sockets or an iOS SDK.

This does not compile or execute the tweak. Run device integration checks separately.
"""

import ast
from email.message import Message
import http.client
import io
from pathlib import Path
import plistlib
import zipfile

import fixture_server as fixture


class MemorySocket:
    def __init__(self, data):
        self.data = data

    def makefile(self, *args, **kwargs):
        return io.BytesIO(self.data)


def get(path, cookie=None):
    handler = fixture.Handler.__new__(fixture.Handler)
    handler.path = path
    handler.command = "GET"
    handler.request_version = "HTTP/1.1"
    handler.requestline = "GET " + path + " HTTP/1.1"
    handler.client_address = ("127.0.0.1", 1)
    handler.headers = Message()
    if cookie:
        handler.headers["Cookie"] = cookie
    handler.wfile = io.BytesIO()
    handler.log_message = lambda *args: None
    handler.do_GET()
    response = http.client.HTTPResponse(MemorySocket(handler.wfile.getvalue()))
    response.begin()
    return response


def main():
    root = Path(__file__).resolve().parent.parent
    plist = plistlib.loads((root / "Receptor.plist").read_bytes())
    assert plist["Filter"]["Bundles"] == ["com.apple.mobilesafari"]
    makefile = (root / "Makefile").read_text()
    sources = next(line.split("=", 1)[1].split() for line in makefile.splitlines()
                   if line.startswith("Receptor_FILES ="))
    assert all((root / name).is_file() for name in sources)
    assert "iphone:clang:5.0:4.0" in makefile and "-fno-objc-arc" in makefile
    ast.parse((root / "tests" / "fixture_server.py").read_text())
    print("PASS: injection plist, source manifest, SDK/MRC settings, Python syntax")

    for path in ["/", "/archive.zip", "/raw.txt", "/attachment", "/unknown", "/unsafe", "/set-cookie"]:
        response = get(path)
        body = response.read()
        assert response.status == 200 and body
        if path in ["/archive.zip", "/attachment", "/unsafe"]:
            with zipfile.ZipFile(io.BytesIO(body)) as archive:
                assert archive.read("hello.txt") == b"Downloaded by Receptor.\n"
        if path == "/attachment":
            assert response.headers["Content-Disposition"] == 'attachment; filename="example.zip"'
        if path == "/unsafe":
            assert "../../" in response.headers["Content-Disposition"]
    redirect = get("/redirect")
    assert redirect.status == 302 and redirect.headers["Location"] == "/attachment"
    assert redirect.read() == b""
    print("PASS: fixture routes, ZIP payloads, redirect and attachment headers")

    for path, status in [("/error.zip", 503), ("/protected.zip", 403), ("/missing", 404)]:
        response = get(path)
        assert response.status == status
        response.read()
    response = get("/protected.zip", cookie="receptor_fixture=allowed")
    assert response.status == 200 and response.read() == fixture.ARCHIVE
    print("PASS: HTTP failures and protected cookie route")

    try:
        get("/truncated.zip").read()
        raise AssertionError("Expected a truncated HTTP response")
    except http.client.IncompleteRead:
        pass
    original_sleep = fixture.time.sleep
    try:
        fixture.time.sleep = lambda seconds: None
        response = get("/slow.zip")
        assert response.status == 200
        assert response.read() == b"R" * (8 * 1024 * 1024)
    finally:
        fixture.time.sleep = original_sleep
    print("PASS: truncated and synthetic slow-transfer responses")
    print("These checks do not compile or execute the Objective-C tweak.")


if __name__ == "__main__":
    main()
