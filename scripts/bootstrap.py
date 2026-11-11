#!/usr/bin/env python3
"""Extract the native runtime closure into Vendor; never installs/upgrades formulae."""
import argparse, hashlib, json, os, pathlib, re, subprocess, tarfile, urllib.request, urllib.parse

ROOT = pathlib.Path(__file__).resolve().parents[1]
VENDOR = ROOT / 'Vendor'
LIB = VENDOR / 'lib'
LIB.mkdir(parents=True, exist_ok=True)
ENV = dict(os.environ, HOMEBREW_NO_AUTO_UPDATE='1')
records = {}
bundled = {}
parser = argparse.ArgumentParser()
parser.add_argument('--refresh', action='store_true', help='Resolve current dependency versions instead of the lock manifest')
options = parser.parse_args()
manifest_path = VENDOR / 'manifest.json'
locked = {} if options.refresh or not manifest_path.exists() else {r['formula']: r for r in json.loads(manifest_path.read_text())['formulae']}
archives = {}

def run(*args):
    return subprocess.check_output(args, env=ENV, text=True).strip()

def bottle(formula):
    if formula in archives: return archives[formula]
    if formula in locked:
        record = locked[formula]
        cache = pathlib.Path.home() / 'Library/Caches/Homebrew/downloads' / record['bottle']
        if not cache.is_file():
            cache = ROOT / '.build/NativeDownloads' / record['bottle']
        if not cache.is_file():
            url = record.get('bottle_url')
            if not url: raise RuntimeError('Locked bottle unavailable; run --refresh to intentionally update dependencies')
            repo = urllib.parse.urlparse(url).path.split('/v2/', 1)[1].split('/blobs/')[0]
            token_url = 'https://ghcr.io/token?' + urllib.parse.urlencode({'service': 'ghcr.io', 'scope': 'repository:' + repo + ':pull'})
            token = json.load(urllib.request.urlopen(token_url, timeout=30))['token']
            request = urllib.request.Request(url, headers={'Authorization': 'Bearer ' + token})
            cache.parent.mkdir(parents=True, exist_ok=True)
            temporary = cache.with_suffix('.download')
            with urllib.request.urlopen(request, timeout=30) as response, temporary.open('wb') as output:
                while chunk := response.read(2 * 1024 * 1024): output.write(chunk)
            temporary.rename(cache)
        if hashlib.file_digest(cache.open('rb'), 'sha256').hexdigest() != record['sha256']:
            raise RuntimeError('Native dependency checksum mismatch: ' + formula)
        records[formula] = record
        archives[formula] = cache
        return cache
    if formula not in records:
        cache = pathlib.Path(run('brew', '--cache', '--force-bottle', formula))
        if not cache.is_file():
            subprocess.run(['brew', 'fetch', '--force-bottle', formula], env=ENV, check=True)
        data = json.loads(run('brew', 'info', '--json=v2', formula))['formulae'][0]
        tag = next(tag for tag in data['bottle']['stable']['files'] if tag in cache.name)
        records[formula] = {'formula': formula, 'version': data['versions']['stable'], 'license': data['license'], 'source': data['urls']['stable'], 'bottle': cache.name, 'bottle_url': data['bottle']['stable']['files'][tag]['url'], 'sha256': hashlib.file_digest(cache.open('rb'), 'sha256').hexdigest()}
    # Ask Homebrew for the exact current bottle, not an arbitrary cached revision.
    archives[formula] = pathlib.Path(run('brew', '--cache', '--force-bottle', formula))
    return archives[formula]

def extract(formula, suffix, destination):
    archive = bottle(formula)
    with tarfile.open(archive) as tar:
        members = tar.getmembers()
        candidates = [m for m in members if m.name.endswith('/' + suffix)]
        if not candidates:
            raise RuntimeError(f'{suffix} absent from {archive.name}')
        member = candidates[0]
        stream = tar.extractfile(member)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(stream.read())
        destination.chmod(0o755)
        notices = VENDOR / 'licenses' / formula
        for m in members:
            if m.isfile() and (re.search(r'(^|/)(COPYING|LICENSE|COPYRIGHT|Copyright|NOTICE)', m.name) or m.name.endswith(('/.brew/' + formula + '.rb', '/.brew/' + formula.split('@')[0] + '.rb')) or m.name.endswith('/sbom.spdx.json')):
                notices.mkdir(parents=True, exist_ok=True)
                (notices / pathlib.Path(m.name).name).write_bytes(tar.extractfile(m).read())

def collect(original, owner=None):
    if original.startswith('@rpath/') and owner:
        original = '/opt/homebrew/opt/' + owner + '/lib/' + original.removeprefix('@rpath/')
    # Both fixed-prefix and relocatable Homebrew bottles are accepted.
    match = re.search(r'(?:/opt/homebrew|@@HOMEBREW_PREFIX@@)/opt/([^/]+)/(.+)', original)
    if not match:
        match = re.search(r'(?:/opt/homebrew/Cellar|@@HOMEBREW_CELLAR@@)/([^/]+)/[^/]+/(.+)', original)
    if not match:
        if original.startswith(('/System/', '/usr/lib/')): return
        raise RuntimeError(f'Unresolved native dependency: {original}')
    formula, suffix = match.groups()
    name = pathlib.Path(suffix).name
    if name in bundled: return
    destination = LIB / name
    bundled[name] = original
    extract(formula, suffix, destination)
    for line in run('otool', '-L', str(destination)).splitlines()[2:]:
        dependency = line.strip().split(' (')[0]
        if dependency.startswith(('/System/', '/usr/lib/')): continue
        collect(dependency, formula)

collect('/opt/homebrew/opt/mpv/lib/libmpv.2.dylib')
with tarfile.open(bottle('mpv')) as tar:
    for member in tar.getmembers():
        if member.isfile() and '/include/mpv/' in member.name:
            out = VENDOR / 'include/mpv' / pathlib.Path(member.name).name
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(tar.extractfile(member).read())

for name in bundled:
    target = LIB / name
    args = ['install_name_tool', '-id', '@rpath/' + name]
    for line in run('otool', '-L', str(target)).splitlines()[2:]:
        dependency = line.strip().split(' (')[0]
        base = pathlib.Path(dependency).name
        if base in bundled: args += ['-change', dependency, '@loader_path/' + base]
    subprocess.run(args + [str(target)], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(['codesign', '--force', '--sign', '-', str(target)], check=True, capture_output=True)
link = LIB / 'libmpv.dylib'
if not link.exists(): link.symlink_to('libmpv.2.dylib')
(VENDOR / 'manifest.json').write_text(json.dumps({'architecture': run('uname', '-m'), 'origin': 'Homebrew bottles; extracted without installation', 'formulae': list(records.values()), 'libraries': bundled}, indent=2) + '\n')
print(f'Prepared {len(bundled)} native libraries in {LIB}')
