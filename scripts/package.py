#!/usr/bin/env python3
import argparse, json, os, pathlib, plistlib, shutil, subprocess

root = pathlib.Path(__file__).resolve().parents[1]
os.chdir(root)
parser = argparse.ArgumentParser()
parser.add_argument('--configuration', choices=['debug', 'release'], default='release')
parser.add_argument('--qa', action='store_true')
parser.add_argument('--version', default='0.2.1')
parser.add_argument('--output', type=pathlib.Path, help='Destination .app path; use a new path while another build is running')
args = parser.parse_args()
subprocess.run(['swift', 'build', '-c', args.configuration], check=True)
bin_dir = pathlib.Path(subprocess.check_output(['swift', 'build', '-c', args.configuration, '--show-bin-path'], text=True).strip())
app = args.output.resolve() if args.output else root / ('dist/LiPlayer QA.app' if args.qa else 'dist/LiPlayer.app')
if app.exists(): shutil.rmtree(app)
contents = app / 'Contents'
for directory in ['MacOS', 'Frameworks', 'Resources/Licenses']:
    (contents / directory).mkdir(parents=True, exist_ok=True)
binary = contents / 'MacOS/LiPlayer'
shutil.copy2(bin_dir / 'LiPlayer', binary)
shutil.copytree(root / 'Vendor/lib', contents / 'Frameworks', dirs_exist_ok=True, symlinks=True)
shutil.copytree(root / 'Vendor/licenses', contents / 'Resources/Licenses', dirs_exist_ok=True)
shutil.copy2(root / 'Vendor/manifest.json', contents / 'Resources/Licenses/native-dependencies.json')
if (root / 'LICENSE').exists(): shutil.copy2(root / 'LICENSE', contents / 'Resources/Licenses/LiPlayer-GPLv3.txt')
if (root / 'NOTICE.md').exists(): shutil.copy2(root / 'NOTICE.md', contents / 'Resources/Licenses/NOTICE.md')
if (root / 'ThirdParty/README.md').exists():
    shutil.copy2(root / 'ThirdParty/README.md', contents / 'Resources/Licenses/SOURCES.md')
    shutil.copy2(root / 'ThirdParty/sources.lock.json', contents / 'Resources/Licenses/sources.lock.json')
    shutil.copytree(root / 'ThirdParty/source-notices', contents / 'Resources/Licenses/SourceNotices', dirs_exist_ok=True)
info = {
    'CFBundleName': 'LiPlayer', 'CFBundleDisplayName': 'LiPlayer',
    'CFBundleIdentifier': 'com.aliahad.liplayer.qa' if args.qa else 'com.aliahad.liplayer', 'CFBundleExecutable': 'LiPlayer',
    'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': args.version, 'CFBundleVersion': '3',
    'LSMinimumSystemVersion': '27.2', 'NSHighResolutionCapable': True,
    'NSPrincipalClass': 'NSApplication', 'LSApplicationCategoryType': 'public.app-category.video',
    'CFBundleIconFile': 'AppIcon',
    'NSHumanReadableCopyright': 'LiPlayer contributors. GPLv3. Third-party notices included.',
    'UTExportedTypeDeclarations': [{'UTTypeIdentifier': 'com.aliahad.liplayer.queue', 'UTTypeDescription': 'LiPlayer Queue', 'UTTypeConformsTo': ['public.json'], 'UTTypeIconFile': 'LiPlayerQueue', 'UTTypeTagSpecification': {'public.filename-extension': ['lpqueue']}}],
    'UTImportedTypeDeclarations': [{'UTTypeIdentifier': 'com.aliahad.videoplayer.queue', 'UTTypeDescription': 'Legacy Video Player Queue', 'UTTypeConformsTo': ['public.json'], 'UTTypeIconFile': 'LiPlayerQueue', 'UTTypeTagSpecification': {'public.filename-extension': ['vpqueue']}}],
    'CFBundleDocumentTypes': [
        {'CFBundleTypeName': 'Media files', 'CFBundleTypeRole': 'Viewer', 'LSHandlerRank': 'Alternate', 'LSItemContentTypes': ['public.movie', 'public.audio'], 'CFBundleTypeExtensions': ['mp4', 'm4v', 'mkv', 'webm', 'mov', 'avi', 'mp3', 'flac', 'wav', 'm4a', 'ts', 'srt', 'ass', 'vtt']},
        {'CFBundleTypeName': 'LiPlayer Queue', 'CFBundleTypeRole': 'Editor', 'LSHandlerRank': 'Owner', 'CFBundleTypeIconFile': 'LiPlayerQueue', 'LSItemContentTypes': ['com.aliahad.liplayer.queue']},
        {'CFBundleTypeName': 'Legacy Video Player Queue', 'CFBundleTypeRole': 'Editor', 'LSHandlerRank': 'Alternate', 'CFBundleTypeIconFile': 'LiPlayerQueue', 'LSItemContentTypes': ['com.aliahad.videoplayer.queue']}
    ]
}
(contents / 'Info.plist').write_bytes(plistlib.dumps(info))
iconset = root / '.build/AppIcon.iconset'
doc_iconset = root / '.build/LiPlayerQueue.iconset'
brand_dir = root / 'Assets'
subprocess.run(['swift', str(root / 'scripts/make-icon.swift'), str(iconset), '--doc-iconset', str(doc_iconset), '--brand-dir', str(brand_dir)], check=True)
subprocess.run(['iconutil', '-c', 'icns', '-o', str(contents / 'Resources/AppIcon.icns'), str(iconset)], check=True)
subprocess.run(['iconutil', '-c', 'icns', '-o', str(contents / 'Resources/LiPlayerQueue.icns'), str(doc_iconset)], check=True)
shutil.copy2(brand_dir / 'LiPlayer-Logo.png', contents / 'Resources/LiPlayerLogo.png')
# Development builds use a local rpath. Distributed bundles resolve only their own libraries.
subprocess.run(['install_name_tool', '-delete_rpath', str(root / 'Vendor/lib'), str(binary)], check=True)
for lib in (contents / 'Frameworks').iterdir():
    if lib.is_symlink(): continue
    for line in subprocess.check_output(['otool', '-L', str(lib)], text=True).splitlines()[2:]:
        dep = line.strip().split(' (')[0]
        if not dep.startswith(('/System/', '/usr/lib/', '@loader_path/')):
            raise RuntimeError(f'Unbundled dependency: {lib.name}: {dep}')
identity = os.environ.get('LIPLAYER_SIGN_IDENTITY') or os.environ.get('VIDEOPLAYER_SIGN_IDENTITY', '-')
for lib in (contents / 'Frameworks').iterdir():
    if not lib.is_symlink(): subprocess.run(['codesign', '--force', '--sign', identity, str(lib)], check=True, capture_output=True)
sign = ['codesign', '--force', '--sign', identity]
if identity != '-': sign += ['--options', 'runtime', '--timestamp']
subprocess.run(sign + [str(app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print(app)
