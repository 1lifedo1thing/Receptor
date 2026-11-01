#!/usr/bin/env python3
"""Create a new package version label while preserving the exact signed payload.

Original published archives are never changed. Only the control Version field is
changed; the bundled app retains its original version and signature.
"""
import argparse
import gzip
import io
from pathlib import Path
import re
import tarfile


def relabel(source, version):
    if not re.fullmatch(r'[0-9][A-Za-z0-9.+:~\-]*', version):
        raise ValueError('Invalid Debian version')
    data = source.read_bytes()
    if not data.startswith(b'!<arch>\n'):
        raise ValueError('Invalid Debian archive')
    result = bytearray(data[:8]); offset = 8; found = False
    identifier = architecture = None
    while offset < len(data):
        header = bytearray(data[offset:offset + 60])
        if len(header) != 60 or header[58:] != b'`\n':
            raise ValueError('Invalid ar member')
        size = int(header[48:58]); name = header[:16].decode('ascii').strip().rstrip('/')
        body = data[offset + 60:offset + 60 + size]
        if len(body) != size:
            raise ValueError('Truncated archive')
        if name == 'control.tar.gz':
            if found:
                raise ValueError('Duplicate control archive')
            output = io.BytesIO()
            with tarfile.open(fileobj=io.BytesIO(body), mode='r:gz') as original, tarfile.open(fileobj=output, mode='w', format=tarfile.GNU_FORMAT) as updated:
                for member in original:
                    content = original.extractfile(member).read() if member.isfile() else None
                    if member.name.lstrip('./') == 'control' and content is not None:
                        text = content.decode('utf-8')
                        fields = dict(line.split(': ', 1) for line in text.splitlines() if ': ' in line and not line[0].isspace())
                        identifier, architecture = fields['Package'], fields['Architecture']
                        text, count = re.subn(r'^Version: [^\r\n]+', 'Version: ' + version, text, flags=re.MULTILINE)
                        if count != 1 or found:
                            raise ValueError('Ambiguous control version')
                        content = text.encode('utf-8'); member.size = len(content); found = True
                    updated.addfile(member, io.BytesIO(content) if content is not None else None)
            body = gzip.compress(output.getvalue(), mtime=0)
            header[48:58] = str(len(body)).ljust(10).encode('ascii')
        result.extend(header); result.extend(body)
        if len(body) % 2: result.extend(b'\n')
        offset += 60 + size + size % 2
    if not found:
        raise ValueError('No gzip control archive')
    return bytes(result), identifier, architecture


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('version')
    parser.add_argument('--output', type=Path, default=Path('packages'))
    args = parser.parse_args()
    content, identifier, architecture = relabel(args.source, args.version)
    destination = args.output / (identifier + '_' + args.version + '_' + architecture + '.deb')
    if destination.exists() and destination.read_bytes() != content:
        raise ValueError('Refusing to replace different existing package bytes')
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(content)
    print('Created ' + str(destination) + '; signed payload unchanged')


if __name__ == '__main__':
    main()
