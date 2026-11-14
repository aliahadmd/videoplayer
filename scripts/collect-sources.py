#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
#
# LiPlayer — Native macOS video player built with Swift, AppKit, SwiftUI, and libmpv.
# Copyright (C) 2026 Ali Ahad <https://aliahad.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
"""Fetch and verify the third-party source files attached to a binary release."""
import argparse, concurrent.futures, hashlib, json, pathlib, subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--lock-new', action='store_true', help='Record first hashes for newly added commit-pinned archives')
args = parser.parse_args()
lock = ROOT / 'ThirdParty/sources.lock.json'
data = json.loads(lock.read_text())
destination = ROOT / '.build/SourceDownloads'
destination.mkdir(parents=True, exist_ok=True)

def fetch(record):
    name = record['file']
    if pathlib.Path(name).name != name: raise ValueError('Invalid source filename')
    path = destination / name
    expected = record.get('sha256')
    if not expected and not args.lock_new: raise ValueError('Missing locked checksum: ' + name)
    if not path.exists():
        temporary = path.with_name(path.name + '.download')
        subprocess.run(['curl', '--fail', '--location', '--silent', '--show-error', '--retry', '2', '--connect-timeout', '15', '--max-time', '180', record['url'], '--output', str(temporary)], check=True)
        temporary.replace(path)
    with path.open('rb') as file: actual = hashlib.file_digest(file, 'sha256').hexdigest()
    if expected and expected != actual: raise ValueError('Source checksum mismatch: ' + name)
    record['sha256'] = actual
    print('Verified ' + name, flush=True)

failures = []
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    futures = {pool.submit(fetch, record): record for record in data['sources']}
    for future in concurrent.futures.as_completed(futures):
        try: future.result()
        except Exception as error:
            failures.append((futures[future]['file'], str(error)))
if failures:
    for name, error in failures: print('FAILED ' + name + ': ' + error)
    raise SystemExit(1)
if args.lock_new: lock.write_text(json.dumps(data, indent=2) + '\n')
print(f'Verified {len(data["sources"])} source files in {destination}')
