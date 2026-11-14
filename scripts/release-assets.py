#!/usr/bin/env python3
"""Create checked release assets from a tested app and committed source tree."""
import argparse, datetime, hashlib, json, pathlib, plistlib, re, subprocess, tarfile, zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--app', type=pathlib.Path, required=True)
parser.add_argument('--version', help='Defaults to the app bundle version')
parser.add_argument('--reuse-dependency-release', help='Reuse an existing public source archive only when native inputs are unchanged')
args = parser.parse_args()
app = args.app.resolve()
output = ROOT / 'dist/github'
output.mkdir(parents=True, exist_ok=True)
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
version = args.version or info['CFBundleShortVersionString']
assert info['CFBundleShortVersionString'] == version
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
assert not subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=normal'], cwd=ROOT).strip(), 'Commit the reviewed source before creating release assets'
commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
report = json.loads((ROOT / 'docs/validation/playback.json').read_text())
assert report['success'] and report['no_homebrew_runtime_dependency']
model_report = json.loads((ROOT / 'docs/validation/model.json').read_text())
assert model_report['success']

def digest(path):
    with path.open('rb') as file: return hashlib.file_digest(file, 'sha256').hexdigest()

binary = output / f'LiPlayer-{version}-macOS-arm64.zip'
subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(binary)], check=True)
with zipfile.ZipFile(binary) as archive: assert archive.testzip() is None
source = output / f'LiPlayer-{version}-source.tar.gz'
subprocess.run(['git', 'archive', '--format=tar.gz', f'--prefix=LiPlayer-{version}-source/', '-o', str(source), commit], cwd=ROOT, check=True)
records = json.loads((ROOT / 'ThirdParty/sources.lock.json').read_text())['sources']
if args.reuse_dependency_release:
    tag = args.reuse_dependency_release
    assert re.fullmatch(r'v\d+\.\d+\.\d+', tag), 'Expected a version tag'
    for name in ['Vendor/manifest.json', 'ThirdParty/sources.lock.json']:
        previous = subprocess.check_output(['git', 'show', f'{tag}:{name}'], cwd=ROOT)
        assert previous == (ROOT / name).read_bytes(), 'Native dependency inputs changed; create a new source archive'
    assert not subprocess.check_output(['git', 'diff', tag, '--', 'ThirdParty/recipes', 'ThirdParty/notices', 'ThirdParty/source-notices'], cwd=ROOT), 'Native recipes or notices changed'
    repo = subprocess.check_output(['gh', 'repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner'], cwd=ROOT, text=True).strip()
    previous = json.loads(subprocess.check_output(['gh', 'api', f'repos/{repo}/releases/tags/{tag}']))
    assert not previous['draft']
    asset = next(asset for asset in previous['assets'] if asset['name'].endswith('-third-party-sources.tar.gz'))
    assert asset['state'] == 'uploaded' and asset['digest'].startswith('sha256:')
    third_party = output / f'LiPlayer-{version}-dependency-sources.json'
    third_party.write_text(json.dumps({'release': tag, 'url': asset['browser_download_url'], 'bytes': asset['size'], 'sha256': asset['digest'].removeprefix('sha256:'), 'native_manifest_sha256': digest(ROOT / 'Vendor/manifest.json'), 'source_files': len(records)}, indent=2) + '\n')
else:
    third_party = output / f'LiPlayer-{version}-third-party-sources.tar.gz'
    prefix = f'LiPlayer-{version}-third-party-sources'
    with tarfile.open(third_party, 'w:gz', compresslevel=1) as archive:
        for name in ['ThirdParty', 'Vendor/manifest.json', 'scripts/bootstrap.py', 'scripts/package.py', 'scripts/collect-sources.py', 'scripts/source-notices.py', 'LICENSE', 'NOTICE.md']:
            archive.add(ROOT / name, arcname=f'{prefix}/{name}')
        for record in records:
            path = ROOT / '.build/SourceDownloads' / record['file']
            assert digest(path) == record['sha256'], 'Source checksum mismatch: ' + record['file']
            archive.add(path, arcname=f'{prefix}/upstream/{record["file"]}')
manifest = {'version': version, 'commit': commit, 'created_at': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'architecture': 'arm64', 'minimum_macos': info['LSMinimumSystemVersion'], 'signing': 'ad hoc; unnotarized', 'playback_checks_passed': len(report['checks']), 'model_tests_passed': model_report['test_count'], 'third_party_source_files': len(records), 'assets': {path.name: {'bytes': path.stat().st_size, 'sha256': digest(path)} for path in [binary, source, third_party]}}
workspace_report = ROOT / 'docs/validation/workspace.json'
if workspace_report.exists():
    workspace = json.loads(workspace_report.read_text())
    assert workspace['success'] and workspace['forced_termination_tested']
    manifest['workspace_checks_passed'] = len(workspace['checks'])
manifest_path = output / 'release-manifest.json'
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
(output / 'SHA256SUMS.txt').write_text(''.join(f'{digest(path)}  {path.name}\n' for path in [binary, source, third_party, manifest_path]))
print(json.dumps(manifest, indent=2))
