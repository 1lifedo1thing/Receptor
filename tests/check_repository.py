#!/usr/bin/env python3
"""Validate repository indexes against the exact packages served to Cydia."""
import bz2
import gzip
import hashlib
import io
from pathlib import Path
import tarfile
import plistlib
import struct

ROOT = Path(__file__).resolve().parent.parent / "docs"


def main():
    raw = (ROOT / "Packages").read_bytes()
    assert gzip.decompress((ROOT / "Packages.gz").read_bytes()) == raw
    assert bz2.decompress((ROOT / "Packages.bz2").read_bytes()) == raw
    entries = raw.decode().strip().split("\n\n")
    for entry in entries:
        fields = dict(line.split(": ", 1) for line in entry.splitlines() if not line.startswith(" ") and ": " in line)
        relative = Path(fields["Filename"])
        assert not relative.is_absolute() and ".." not in relative.parts
        data = (ROOT / relative).read_bytes()
        assert data.startswith(b"!<arch>\n")
        assert int(fields["Size"]) == len(data)
        for field, algorithm in [("MD5sum", "md5"), ("SHA1", "sha1"), ("SHA256", "sha256")]:
            assert fields[field] == hashlib.new(algorithm, data).hexdigest()
        # Independently inspect the package control archive and staged tweak contents.
        members = {}
        offset = 8
        while offset < len(data):
            header = data[offset:offset + 60]
            size = int(header[48:58])
            members[header[:16].decode().strip().rstrip("/")] = data[offset + 60:offset + 60 + size]
            offset += 60 + size + size % 2
        control_data = next(value for name, value in members.items() if name.startswith("control.tar"))
        payload_data = next(value for name, value in members.items() if name.startswith("data.tar"))
        with tarfile.open(fileobj=io.BytesIO(control_data), mode="r:*") as archive:
            control = next(archive.extractfile(member).read().decode() for member in archive
                           if member.name.lstrip("./") == "control")
            scripts = {member.name.lstrip('./'): (member.mode, archive.extractfile(member).read())
                       for member in archive if member.isfile() and member.name.lstrip('./') in ('postinst', 'prerm')}
        assert "Package: " + fields["Package"] + "\n" in control
        assert "Version: " + fields["Version"] + "\n" in control
        assert "Architecture: " + fields["Architecture"] + "\n" in control
        with tarfile.open(fileobj=io.BytesIO(payload_data), mode="r:*") as archive:
            members_info = {member.name.lstrip("./"): member for member in archive.getmembers()}
            payload = {name: archive.extractfile(member).read() for name, member in members_info.items() if member.isfile()}
            names = set(payload)
        if fields["Package"] == "com.jajaengland.repoicons":
            assert payload["Library/JajaEngland/Icons/Receptor.png"].startswith(b"\x89PNG\r\n\x1a\n")
            assert payload["Library/JajaEngland/Icons/Repo.png"].startswith(b"\x89PNG\r\n\x1a\n")
            continue
        assert "Library/MobileSubstrate/DynamicLibraries/Receptor.dylib" in names
        assert "Library/MobileSubstrate/DynamicLibraries/Receptor.plist" in names
        if fields["Version"] != "1.0.0":
            app = plistlib.loads(payload["Applications/Receptor.app/Info.plist"])
            assert app["CFBundleIdentifier"] == "com.receptor.app"
            assert app["MinimumOSVersion"] == "4.0"
            # Relabeled beta-1 packages keep their original signed app payload intact.
            original = {"1.5.0b1": "1.5.0", "1.6.0b1": "1.6.0"}.get(fields["Version"], fields["Version"])
            assert app["CFBundleVersion"] == original
            ca = payload["Library/Application Support/Receptor/cacert.pem"]
            assert b"-----BEGIN CERTIFICATE-----" in ca
            assert ca == (ROOT.parent / "layout/Library/Application Support/Receptor/cacert.pem").read_bytes()
            assert "Library/Application Support/Receptor/licenses/mbedtls.txt" in names
            for icon in app["CFBundleIconFiles"]:
                assert payload["Applications/Receptor.app/" + icon].startswith(b"\x89PNG\r\n\x1a\n")
            for binary_name in ["Applications/Receptor.app/ReceptorApp", "Library/MobileSubstrate/DynamicLibraries/Receptor.dylib"]:
                binary = payload[binary_name]
                magic, cpu, subtype = struct.unpack_from("<III", binary)
                assert (magic, cpu, subtype) == (0xfeedface, 12, 9)
                count = struct.unpack_from("<I", binary, 16)[0]
                offset = 28
                minimum = None
                for _ in range(count):
                    command, size = struct.unpack_from("<II", binary, offset)
                    if command == 0x25:
                        minimum = struct.unpack_from("<II", binary, offset + 8)
                    offset += size
                assert minimum == (0x40000, 0x50000)
            if "usr/libexec/receptor-package-helper" in payload:
                name = "usr/libexec/receptor-package-helper"
                helper = members_info[name]
                assert helper.uid == 0 and helper.gid == 0 and helper.mode == 0o4755
                binary = payload[name]
                assert struct.unpack_from("<III", binary) == (0xfeedface, 12, 9)
                assert b"csops" in binary and b"/Applications/Receptor.app/ReceptorApp" in binary
                assert b"/usr/bin/apt-get" in binary and b"/usr/bin/apt-cache" in binary
                assert b"receptor-packages.lock" in binary and b"last-operation.plist" in binary
                assert b"RC_PKG_TEST_ROOT" not in binary
                count = struct.unpack_from("<I", binary, 16)[0]; offset = 28; minimum = None
                for _ in range(count):
                    command, size = struct.unpack_from("<II", binary, offset)
                    if command == 0x25: minimum = struct.unpack_from("<II", binary, offset + 8)
                    offset += size
                assert minimum == (0x40000, 0x50000)
            if "usr/libexec/receptor-remote-agent" in payload:
                for name in ['usr/libexec/receptor-remote-agent', 'usr/libexec/receptor-file-helper']:
                    member = members_info[name]
                    assert member.uid == member.gid == 0 and member.mode == 0o755
                    assert struct.unpack_from('<III', payload[name]) == (0xfeedface, 12, 9)
                    assert b'RC_REMOTE_TEST_ROOT' not in payload[name]
                name = 'Library/LaunchDaemons/com.receptor.remote.plist'
                assert members_info[name].mode == 0o644 and members_info[name].uid == 0
                job = plistlib.loads(payload[name])
                assert job['UserName'] == 'root' and 'RunAtLoad' not in job
                assert job['KeepAlive'] == {'PathState': {'/var/lib/receptor/remote.plist': True}}
                assert job['ProgramArguments'] == ['/usr/libexec/receptor-remote-agent']
                assert scripts['prerm'][0] & 0o111 and b'remove|deconfigure)' in scripts['prerm'][1]
            if "usr/libexec/receptor-deb-helper" in payload:
                helper_name = "usr/libexec/receptor-deb-helper"
                helper = members_info[helper_name]
                assert helper.uid == 0 and helper.gid == 0 and helper.mode == 0o4755
                assert b"/Applications/Receptor.app/ReceptorApp" in payload[helper_name]
                assert b"/usr/bin/dpkg" in payload[helper_name]
                assert b"csops" in payload[helper_name]
                assert members_info["Applications/Receptor.app"].uid == 0
                assert not members_info["Applications/Receptor.app"].mode & 0o022
                assert not members_info["Applications/Receptor.app/ReceptorApp"].mode & 0o022
                helper_bytes = payload[helper_name]
                assert struct.unpack_from("<III", helper_bytes) == (0xfeedface, 12, 9)
                count = struct.unpack_from("<I", helper_bytes, 16)[0]
                offset = 28
                minimum = None
                for _ in range(count):
                    command, size = struct.unpack_from("<II", helper_bytes, offset)
                    if command == 0x25: minimum = struct.unpack_from("<II", helper_bytes, offset + 8)
                    offset += size
                assert minimum == (0x40000, 0x50000)
    algorithm = None
    checks = 0
    for line in (ROOT / "Release").read_text().splitlines():
        if line in ["MD5Sum:", "SHA1:", "SHA256:"]:
            algorithm = {"MD5Sum:": "md5", "SHA1:": "sha1", "SHA256:": "sha256"}[line]
        elif line.startswith(" "):
            expected, size, name = line.split()
            data = (ROOT / name).read_bytes()
            assert len(data) == int(size)
            assert hashlib.new(algorithm, data).hexdigest() == expected
            checks += 1
    assert checks == 9
    assert (ROOT / ".nojekyll").exists()
    print("PASS: %d package(s), gzip/bzip2 indexes, payloads and 9 Release checksums" % len(entries))


if __name__ == "__main__":
    main()
