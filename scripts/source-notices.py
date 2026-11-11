#!/usr/bin/env python3
"""Preserve upstream copyright and license files in the distributed app."""
import json, pathlib, re, shutil, tarfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
records = json.loads((ROOT / 'ThirdParty/sources.lock.json').read_text())['sources']
output = ROOT / 'ThirdParty/source-notices'
output.mkdir(parents=True, exist_ok=True)
count = 0
for record in records:
    archive = ROOT / '.build/SourceDownloads' / record['file']
    if record['kind'] == 'license':
        shutil.copy2(archive, ROOT / 'ThirdParty' / record['file'])
        continue
    if not tarfile.is_tarfile(archive): continue
    with tarfile.open(archive) as tar:
        for member in tar:
            path = pathlib.PurePosixPath(member.name)
            if not member.isfile() or '..' in path.parts or path.is_absolute(): continue
            if not re.match(r'^(licen[sc]e|copying|copyright|notice|ftl)([._-]|$)', path.name, re.I): continue
            destination = output / record['component'] / record['kind'] / pathlib.Path(*path.parts)
            destination.parent.mkdir(parents=True, exist_ok=True)
            with tar.extractfile(member) as source, destination.open('wb') as target: shutil.copyfileobj(source, target)
            count += 1
print(f'Preserved {count} upstream notice files')
