#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""check-j773g-packages.py [--download] — sanity checks for packaging/j773g.

For every PKGBUILD: it parses, names its package and version, has one
checksum per source, pins every download with a real checksum, ships every
local source and install file it lists, and every other file next to it is
at least documented. --download also fetches each download and verifies its
checksum (what makepkg would do first).
"""
import hashlib
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PACKAGES = REPO / 'packaging/j773g'
ARRAYS = ('pkgname', 'pkgver', 'pkgrel', 'arch', 'source', 'sha256sums', 'b2sums', 'install')
DIGESTS = {'sha256sums': ('sha256', 64), 'b2sums': ('blake2b', 128)}

# Prints each variable as name=value records, NUL-separated, from a clean shell.
DUMP = r'''
set -e
source ./PKGBUILD >/dev/null
for name in "$@"; do
  declare -n ref=$name
  for value in "${ref[@]}"; do printf '%s=%s\0' "$name" "$value"; done
done
'''


def load(directory):
    result = subprocess.run([shutil.which('bash'), '-c', DUMP, 'dump', *ARRAYS], cwd=directory,
                            capture_output=True, env={'PATH': '/usr/bin:/bin'})
    if result.returncode:
        raise ValueError('PKGBUILD does not source cleanly: ' + result.stderr.decode().strip())
    fields = {name: [] for name in ARRAYS}
    for record in result.stdout.split(b'\0')[:-1]:
        name, value = record.decode().split('=', 1)
        fields[name].append(value)
    return fields


def split_source(entry):
    """(file name makepkg uses, URL or None for a local file)."""
    name, _, url = entry.rpartition('::')
    if '://' not in url:
        return url, None
    return name or url.rsplit('/', 1)[1], url


def documented(name):
    """A file kept beside a PKGBUILD without being a source must at least be mentioned."""
    hits = subprocess.run(['git', 'grep', '-l', '-F', name, '--', '.', ':!.gitattributes'],
                          cwd=REPO, capture_output=True, text=True).stdout.split()
    return bool(hits)


def check(directory, download):
    errors = []
    fields = load(directory)
    for name in ('pkgname', 'pkgver', 'pkgrel', 'arch'):
        if not fields[name]:
            errors.append(f'{name} is empty')
    if not ({'aarch64', 'any'} & set(fields['arch'])):
        errors.append(f'arch {fields["arch"]} builds neither aarch64 nor any')
    sums = [(kind, fields[kind]) for kind in DIGESTS if fields[kind]]
    if not sums:
        errors.append('no sha256sums or b2sums')
    sources = [split_source(entry) for entry in fields['source']]
    for kind, values in sums:
        if len(values) != len(sources):
            errors.append(f'{len(sources)} sources but {len(values)} {kind}')
    listed = {'PKGBUILD'}
    for index, (name, url) in enumerate(sources):
        listed.add(name)
        for kind, values in sums:
            value = values[index] if index < len(values) else None
            if url and (value == 'SKIP' or value is None or
                        len(value) != DIGESTS[kind][1] or value.strip('0123456789abcdef')):
                errors.append(f'download {name} is not pinned by a {kind} entry ({value})')
        if url is None and not (directory / name).is_file():
            errors.append(f'local source {name} is missing')
        if url and download and not errors:
            errors += verify(name, url, [(kind, values[index]) for kind, values in sums])
    for install in fields['install']:
        listed.add(install)
        if not (directory / install).is_file():
            errors.append(f'install file {install} is missing')
    for path in sorted(directory.iterdir()):
        if path.name not in listed and not documented(path.name):
            errors.append(f'{path.name} is neither a source nor mentioned anywhere')
    return errors


def verify(name, url, sums):
    with tempfile.TemporaryFile() as data:
        request = urllib.request.Request(url, headers={'User-Agent': 'j773g-ci'})
        with urllib.request.urlopen(request, timeout=300) as response:
            while chunk := response.read(1 << 20):
                data.write(chunk)
        errors = []
        for kind, expected in sums:
            data.seek(0)
            digest = hashlib.file_digest(data, DIGESTS[kind][0]).hexdigest()
            if digest != expected:
                errors.append(f'download {name} has {kind[:-4]} {digest}, PKGBUILD pins {expected}')
        return errors


def main():
    download = sys.argv[1:] == ['--download']
    if sys.argv[1:] and not download:
        sys.exit(__doc__.strip())
    failed = False
    for directory in sorted(path.parent for path in PACKAGES.glob('*/PKGBUILD')):
        errors = check(directory, download)
        print(f'{"FAIL" if errors else "ok  "} {directory.relative_to(REPO)}')
        for error in errors:
            print('     ' + error)
        failed |= bool(errors)
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
