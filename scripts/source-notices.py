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
