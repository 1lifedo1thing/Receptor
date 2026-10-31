#!/usr/bin/env python3
"""Validate repository indexes against the exact packages served to Cydia."""
import bz2
import gzip
import hashlib
import io
from pathlib import Path
import tarfile

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
        assert "Package: " + fields["Package"] + "\n" in control
        assert "Version: " + fields["Version"] + "\n" in control
        assert "Architecture: iphoneos-arm\n" in control
        with tarfile.open(fileobj=io.BytesIO(payload_data), mode="r:*") as archive:
            names = {member.name.lstrip("./") for member in archive}
        assert "Library/MobileSubstrate/DynamicLibraries/Receptor.dylib" in names
        assert "Library/MobileSubstrate/DynamicLibraries/Receptor.plist" in names
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
