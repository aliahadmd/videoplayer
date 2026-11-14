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
"""Exercise folder/session persistence across clean exits and a forced process kill."""
import argparse, json, pathlib, shutil, subprocess, tempfile, time

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--app', type=pathlib.Path, default=ROOT / 'dist/LiPlayer QA.app')
parser.add_argument('--stay-open', action='store_true')
args = parser.parse_args()
directory = pathlib.Path(tempfile.mkdtemp(prefix='Workspace-', dir=ROOT / '.build/Fixtures'))
tree = directory / 'Tree'
for path in ['Season 2/Extras', 'Season 10']:
    (tree / path).mkdir(parents=True)
for name in ['Episode 2.mp4', 'Episode 10.mp4', 'Season 2/Episode 1.mp4', 'Season 2/Episode 2.mp4', 'Season 2/Extras/Clip.mp4']:
    shutil.copy2(ROOT / '.build/Fixtures/Sample.mp4', tree / name)
reports = []
for phase in ['save', 'crash', 'restore']:
    command = [str(args.app.resolve() / 'Contents/MacOS/LiPlayer'), '--workspace-self-test', str(directory), '--workspace-phase', phase]
    if args.stay_open and phase == 'restore': command.append('--stay-open')
    log = (ROOT / f'.build/verification/workspace-{phase}.log').open('w')
    process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
    report_path = directory / f'{phase}.json'
    try:
        deadline = time.monotonic() + 75
        while not report_path.exists() and process.poll() is None and time.monotonic() < deadline: time.sleep(0.2)
        assert report_path.exists(), f'{phase} produced no report; see {log.name}'
        report = json.loads(report_path.read_text())
        assert report['success'], json.dumps(report, indent=2)
        reports.append(report)
        if phase == 'crash':
            process.kill(); process.wait(timeout=10)
        elif args.stay_open and phase == 'restore':
            print('UI_READY ' + str(directory), flush=True)
            assert process.wait() == 0
        else: assert process.wait(timeout=20) == 0, f'{phase} failed to quit cleanly'
    finally:
        if process.poll() is None: process.kill(); process.wait(timeout=10)
        log.close()
result = {'success': True, 'forced_termination_tested': True, 'checks': sum((report['checks'] for report in reports), []), 'phases': reports}
(ROOT / 'docs/validation/workspace.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({'success': True, 'checks': len(result['checks']), 'forced_termination_tested': True}, indent=2))
