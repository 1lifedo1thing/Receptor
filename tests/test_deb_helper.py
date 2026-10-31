#!/usr/bin/env python3
"""Exercise helper file/command handling without root or the host package manager.

Test mode is explicitly forbidden in Apple builds. The fake dpkg only records
arguments and simulates outcomes inside a temporary directory.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    with tempfile.TemporaryDirectory(prefix="receptor-deb-tests-") as directory:
        base = Path(directory)
        downloads, private = base / "downloads", base / "private"
        downloads.mkdir()
        private.mkdir()
        config, record = base / "config.json", base / "record.json"
        fake = base / "fake-dpkg"
        fake.write_text("#!/usr/bin/python3 -I\n" + f"CONFIG={str(config)!r}\nRECORD={str(record)!r}\n" + r'''
import hashlib, json, os, pathlib, stat, sys
settings=json.loads(pathlib.Path(CONFIG).read_text())
calls=json.loads(pathlib.Path(RECORD).read_text()) if pathlib.Path(RECORD).exists() else []
assert "RC_INJECTED" not in os.environ and "DPKG_ROOT" not in os.environ
assert os.environ["PATH"] == "/usr/bin:/bin:/usr/sbin:/sbin"
assert sys.stdin.read() == ""
package=pathlib.Path(sys.argv[-1])
assert package.name == "package.deb" and package.is_absolute()
assert stat.S_IMODE(package.stat().st_mode) == 0o600
assert stat.S_IMODE(package.parent.stat().st_mode) == 0o700
data=package.read_bytes()
calls.append({"arguments":sys.argv[1:], "hash":hashlib.sha256(data).hexdigest()})
pathlib.Path(RECORD).write_text(json.dumps(calls))
simulate=sys.argv[1] == "--no-act"
assert sys.argv[1:] == (["--no-act", "--install", str(package)] if simulate else ["--install", str(package)])
if simulate and settings.get("preflight_failure"):
    print("dependency problems: required-package is not installed")
    sys.exit(1)
if simulate and settings.get("mutate_source"):
    pathlib.Path(settings["mutate_source"]).write_bytes(b"!<arch>\nchanged after preflight")
if not simulate and settings.get("install_failure"):
    print("post-installation script returned error exit status 17")
    sys.exit(17)
if not simulate:
    print("Setting up fixture-package")
    if settings.get("large_log"): print("x" * 100000)
    print("FINAL-LOG-MARKER")
''')
        fake.chmod(0o755)
        helper = base / "helper"
        definitions = ["-DRC_HELPER_TEST=1", f"-DRC_CALLER_UID={os.getuid()}",
                       '-DRC_DOWNLOADS_DIR="' + str(downloads) + '"',
                       '-DRC_DPKG_BINARY="' + str(fake) + '"',
                       '-DRC_STAGING_PARENT="' + str(private) + '"']
        subprocess.run(["cc", "-std=gnu99", "-Wall", "-Wextra", "-Werror", *definitions,
                        str(ROOT / "Tools/receptor-deb-helper.c"), "-o", str(helper)], check=True)
        original = b"!<arch>\nfixture package bytes\n"

        def reset(settings=None):
            config.write_text(json.dumps(settings or {}))
            record.unlink(missing_ok=True)

        def run(name, expected):
            result = subprocess.run([str(helper), name], capture_output=True, text=True, timeout=10,
                                    env={**os.environ, "RC_INJECTED": "bad", "DPKG_ROOT": "/not-allowed"})
            assert result.returncode == expected, (name, result.returncode, result.stdout, result.stderr)
            assert not list(private.iterdir()), "Private staging was not cleaned"
            return result.stdout + result.stderr

        def stage(name, data=original):
            path = downloads / name
            path.write_bytes(data)
            path.chmod(0o600)
            return path

        name = ".receptor-deb-fixture-123456789.deb"
        path = stage(name)
        reset()
        run(name, 0)
        calls = json.loads(record.read_text())
        assert len(calls) == 2 and path.read_bytes() == original
        assert all(call["hash"] == hashlib.sha256(original).hexdigest() for call in calls)
        print("PASS: preflight/install argv, clean environment, private copy, saved file preservation")

        reset({"preflight_failure": True})
        assert "dependency problems" in run(name, 1)
        assert len(json.loads(record.read_text())) == 1
        reset({"install_failure": True})
        assert "exit status 17" in run(name, 17)
        assert path.read_bytes() == original
        print("PASS: dependency failure stops install; native failure/output preserved")

        reset({"mutate_source": str(path)})
        run(name, 0)
        calls = json.loads(record.read_text())
        assert calls[0]["hash"] == calls[1]["hash"] == hashlib.sha256(original).hexdigest()
        path.write_bytes(original)
        print("PASS: package snapshot cannot change between preflight and installation")

        for bad in ["../escape.deb", "--force-all", ".receptor-deb-../escape.deb"]:
            reset()
            run(bad, 2)
            assert not record.exists()
        link = downloads / ".receptor-deb-symbolic-123456789.deb"
        link.symlink_to(path)
        reset()
        run(link.name, 2)
        assert not record.exists()
        link.unlink()
        os.link(path, link)
        run(link.name, 2)
        link.unlink()
        path.chmod(0o666)
        run(name, 2)
        path.chmod(0o600)
        invalid = stage(".receptor-deb-invalid-123456789.deb", b"Not an archive at all")
        run(invalid.name, 2)
        print("PASS: traversal, option arguments, symlinks, hardlinks, writable sources and invalid archives rejected")

        unusual = stage(".receptor-deb-123;touch SENTINEL.deb")
        reset()
        run(unusual.name, 0)
        assert not (downloads / "SENTINEL").exists()
        assert all(";" not in arg for call in json.loads(record.read_text()) for arg in call["arguments"])
        reset({"large_log": True})
        output = run(name, 0)
        assert "FINAL-LOG-MARKER" in output and len(output) < 66000
        print("PASS: shell metacharacters remain data; output is bounded and includes the log tail")
    print("Device-only setuid/caller-code-hash authorization and real iOS dpkg still require on-device testing.")


if __name__ == "__main__":
    main()
