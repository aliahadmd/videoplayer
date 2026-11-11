#!/usr/bin/env python3
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
