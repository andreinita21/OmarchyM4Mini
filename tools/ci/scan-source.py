#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Scan every tracked regular file; attributes cannot hide content from antivirus."""
from pathlib import Path
import subprocess
import tempfile


def inventory(root):
    raw = subprocess.check_output(['git', 'ls-files', '--stage', '-z'], cwd=root)
    records = []
    for record in raw.split(b'\0'):
        if not record:
            continue
        metadata, name = record.split(b'\t', 1)
        mode, _, stage = metadata.split()
        if stage != b'0':
            raise ValueError('Non-regular or unmerged tracked file requires review')
        if any(value in name for value in (b'\n', b'\r')):
            raise ValueError('Newline in tracked path is not supported')
        records.append((mode, name.decode('utf-8')))
    regular = {name for mode, name in records if mode in (b'100644', b'100755')}
    paths = []
    for mode, name in records:
        path = root / name
        if mode == b'120000':
            # A link to another tracked regular file is scanned through that file.
            target, base = path.resolve(), root.resolve()
            if not path.is_symlink() or not target.is_relative_to(base) or \
                    target.relative_to(base).as_posix() not in regular:
                raise ValueError('Symlink must point to a tracked regular file in the repository')
            continue
        if mode not in (b'100644', b'100755'):
            raise ValueError('Non-regular or unmerged tracked file requires review')
        if path.is_symlink() or not path.is_file() or path.stat().st_size > 100 * 1024**2:
            raise ValueError('Tracked file is missing, oversized or a symlink')
        with path.open('rb') as stream:
            if stream.read(43).startswith(b'version https://git-lfs.github.com/spec/v1'):
                raise ValueError('LFS payload must be materialized and reviewed before scanning')
        paths.append(str(path))
    if not paths:
        raise ValueError('No tracked files to scan')
    return paths


def scan(root):
    paths = inventory(root.resolve())
    with tempfile.TemporaryDirectory() as temp:
        listing = Path(temp) / 'files.txt'
        listing.write_text('\n'.join(paths) + '\n')
        subprocess.run(['clamscan', '--infected', '--alert-encrypted=yes',
                        '--alert-exceeds-max=yes', '--max-filesize=100M',
                        '--max-scansize=500M', '--max-recursion=20',
                        '--file-list=' + str(listing)], check=True)
    print(f'Antivirus completed for all {len(paths)} tracked files.')


if __name__ == '__main__':
    scan(Path.cwd())
