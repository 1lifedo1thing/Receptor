#!/usr/bin/env python3
"""Publish a built .deb into the flat Cydia repository under docs/."""
import argparse
import bz2
from datetime import datetime, timezone
from email.utils import format_datetime
import gzip
import hashlib
import io
from pathlib import Path
import shutil
import tarfile

ROOT = Path(__file__).resolve().parent.parent


def control_text(path):
    data = path.read_bytes()
    if not data.startswith(b"!<arch>\n"):
        raise ValueError("Not a Debian package: " + str(path))
    offset = 8
    while offset + 60 <= len(data):
        header = data[offset:offset + 60]
        if header[58:60] != b"`\n":
            raise ValueError("Invalid ar member")
        name = header[:16].decode("ascii").strip().rstrip("/")
        size = int(header[48:58])
        start = offset + 60
        if name.startswith("control.tar"):
            with tarfile.open(fileobj=io.BytesIO(data[start:start + size]), mode="r:*") as archive:
                for member in archive:
                    if member.isfile() and member.name.lstrip("./") == "control":
                        return archive.extractfile(member).read().decode("utf-8").strip()
        offset = start + size + size % 2
    raise ValueError("No package control file: " + str(path))


def digest(data, algorithm):
    return hashlib.new(algorithm, data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", nargs="?", type=Path)
    args = parser.parse_args()
    version = next(line.split(":", 1)[1].strip() for line in (ROOT / "control").read_text().splitlines() if line.startswith("Version:"))
    package = (args.package or ROOT / ("packages/com.receptor.downloadmanager_%s_iphoneos-arm.deb" % version)).resolve(strict=True)
    # Validate metadata before copying a package into the published tree.
    control_text(package)
    output = ROOT / "docs"
    pool = output / "debs"
    pool.mkdir(parents=True, exist_ok=True)
    destination = pool / package.name
    if package != destination.resolve():
        shutil.copyfile(package, destination)
    entries = []
    for path in sorted(pool.glob("*.deb")):
        data = path.read_bytes()
        entries.append(control_text(path) + "\n" + "\n".join([
            "Filename: " + path.relative_to(output).as_posix(),
            "Size: " + str(len(data)),
            "MD5sum: " + digest(data, "md5"),
            "SHA1: " + digest(data, "sha1"),
            "SHA256: " + digest(data, "sha256"),
        ]))
    packages = ("\n\n".join(entries) + "\n\n").encode("utf-8")
    (output / "Packages").write_bytes(packages)
    (output / "Packages.gz").write_bytes(gzip.compress(packages, mtime=0))
    (output / "Packages.bz2").write_bytes(bz2.compress(packages))
    release = [
        "Origin: Receptor", "Label: Receptor", "Suite: stable", "Codename: receptor",
        "Version: 1.0", "Architectures: iphoneos-arm", "Components: main",
        "Description: Receptor downloads for legacy iOS 4 through 6",
        "Date: " + format_datetime(datetime.now(timezone.utc), usegmt=True),
    ]
    for title, algorithm in [("MD5Sum", "md5"), ("SHA1", "sha1"), ("SHA256", "sha256")]:
        release.append(title + ":")
        for name in ["Packages", "Packages.gz", "Packages.bz2"]:
            data = (output / name).read_bytes()
            release.append(" %s %d %s" % (digest(data, algorithm), len(data), name))
    (output / "Release").write_text("\n".join(release) + "\n", encoding="utf-8", newline="\n")
    (output / ".nojekyll").touch()
    print("Updated flat Cydia repository: " + str(output))
    print("Source URL: https://jajaengland.github.io/Receptor/")


if __name__ == "__main__":
    main()
