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
"""Run real playback against generated files and a loopback HTTP range server."""
import argparse, functools, http.server, json, os, pathlib, re, ssl, subprocess, tempfile, threading, urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
FIXTURES = ROOT / '.build/Fixtures'
parser = argparse.ArgumentParser()
parser.add_argument('--app', type=pathlib.Path, default=ROOT / 'dist/LiPlayer QA.app')
parser.add_argument('--stay-open', action='store_true')
parser.add_argument('--https-url', help='Optional trusted public HTTPS media URL for an online check')
args = parser.parse_args()
requests = []

class RangeHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_): pass
    def send_head(self):
        path = pathlib.Path(self.translate_path(self.path))
        if not path.is_file(): self.send_error(404); return None
        file = path.open('rb'); size = path.stat().st_size
        start, end = 0, size - 1
        requested = self.headers.get('Range')
        if requested:
            match = re.fullmatch(r'bytes=(\d+)-(\d*)', requested)
            if not match:
                file.close(); self.send_error(416); return None
            start = int(match[1]); end = min(int(match[2]), end) if match[2] else end
            if start > end:
                file.close(); self.send_error(416); return None
        requests.append({'range': requested is not None, 'status': 206 if requested else 200})
        self.send_response(206 if requested else 200)
        self.send_header('Content-Type', self.guess_type(str(path)))
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Content-Length', str(end - start + 1))
        if requested: self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
        self.end_headers(); file.seek(start)
        self.remaining = end - start + 1
        return file
    def copyfile(self, source, destination):
        remaining = self.remaining
        try:
            while remaining:
                chunk = source.read(min(128 * 1024, remaining))
                if not chunk: break
                destination.write(chunk); remaining -= len(chunk)
        except (BrokenPipeError, ConnectionResetError): pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(RangeHandler, directory=str(FIXTURES)))
server.daemon_threads = True
threading.Thread(target=server.serve_forever, daemon=True).start()
url = f'http://127.0.0.1:{server.server_port}/Sample.mp4'
request = urllib.request.Request(url, headers={'Range': 'bytes=0-63'})
with urllib.request.urlopen(request) as response:
    assert response.status == 206 and len(response.read()) == 64, 'Range server preflight failed'
report = FIXTURES / 'SelfTest.json'
if report.exists(): report.unlink()
command = [str(args.app.resolve() / 'Contents/MacOS/LiPlayer'), '--self-test', str(FIXTURES), '--http-test-url', url]
tls_directory = tempfile.TemporaryDirectory(prefix='liplayer-tls-')
tls_path = pathlib.Path(tls_directory.name)
subprocess.run(['/usr/bin/openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', str(tls_path / 'key.pem'), '-out', str(tls_path / 'cert.pem'), '-days', '1', '-subj', '/CN=localhost'], check=True, capture_output=True)
tls_server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(RangeHandler, directory=str(FIXTURES)))
tls_server.daemon_threads = True
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(tls_path / 'cert.pem', tls_path / 'key.pem')
tls_server.socket = context.wrap_socket(tls_server.socket, server_side=True)
threading.Thread(target=tls_server.serve_forever, daemon=True).start()
command += ['--untrusted-https-test-url', f'https://localhost:{tls_server.server_port}/Sample.mp4']
if args.https_url: command += ['--https-test-url', args.https_url]
isolation = pathlib.Path('/usr/bin/sandbox-exec')
if isolation.exists(): command = [str(isolation), '-p', '(version 1)(allow default)(deny file-read* (subpath "/opt/homebrew"))', *command]
if args.stay_open: command.append('--stay-open')
log = ROOT / '.build/runtime-verification.log'
try:
    with log.open('w') as output:
        result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, timeout=None if args.stay_open else 150)
finally:
    server.shutdown(); server.server_close()
    tls_server.shutdown(); tls_server.server_close(); tls_directory.cleanup()
data = json.loads(report.read_text())
loaded = data.get('bundled_libraries', [])
assert result.returncode == 0 and data.get('success'), json.dumps(data, indent=2)
assert data.get('homebrew_libraries_loaded') is False, 'Runtime loaded a library from Homebrew'
assert 'libmpv.2.dylib' in loaded, 'Could not verify bundled libmpv loading'
data['bundle_libraries_loaded'] = len(loaded)
data['http_requests_served'] = len(requests)
data['no_homebrew_runtime_dependency'] = True
data['homebrew_filesystem_denied'] = isolation.exists()
if args.https_url: data['trusted_https_test_url'] = args.https_url
destination = ROOT / 'docs/validation'
destination.mkdir(parents=True, exist_ok=True)
(destination / 'playback.json').write_text(json.dumps(data, indent=2) + '\n')
print(json.dumps({'success': True, 'checks': len(data['checks']), 'bundled_libraries': len(loaded), 'http_requests': len(requests)}, indent=2))
