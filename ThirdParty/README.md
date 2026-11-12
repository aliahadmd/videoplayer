# Dependency sources and rebuilding

The downloadable app links the 50 native libraries listed in [Vendor/manifest.json](../Vendor/manifest.json), from 42 Homebrew formulae. The application is distributed under GPLv3; individual dependencies retain their original licenses. Read the full notices and upstream license texts rather than treating manifest license identifiers as replacements for them.

The [v0.2.1 release](https://github.com/aliahadmd/videoplayer/releases/tag/v0.2.1) provides the matching application source archive beside the binary download, at no additional charge. The native dependencies are unchanged from v0.1.0: their full sources are available in the shared [third-party source archive](https://github.com/aliahadmd/videoplayer/releases/download/v0.1.0/VideoPlayer-0.1.0-third-party-sources.tar.gz), SHA-256 `fdad2bd2d76001ad94ab7b3a464c908a0fb7b160a329e8f30f35a84ed22bef73`. The v0.2.1 dependency-source reference asset records this URL/hash; its release notes link directly to it next to the app download.

Download **both** the matching application-source archive and that shared dependency-source archive for the application's source plus its bundled libraries. Use the build scripts from the matching application source; the shared archive retains earlier packaging scripts for provenance. The third-party archive includes upstream source tarballs, required build resources, Homebrew patches, source checksums, original recipes, notices and the native dependency manifest. A GitHub-generated source ZIP contains the repository but does not contain the large dependency source tarballs. Keep the shared source asset available while either release is distributed.

## Contents

- `sources.lock.json`: immutable source URLs/revisions and SHA-256 hashes; `scripts/collect-sources.py` verifies downloaded bytes.
- `recipes/`: the recipes shipped in the pinned bottles, plus header-only dependency recipes. These contain configure flags, inline changes and embedded patches. External patch files and resource sources are in the dependency source archive.
- `notices/`: license texts and SPDX metadata extracted from the bottles.
- `source-notices/`: additional copyright/license/notice files preserved from upstream and embedded resource sources. These also ship inside the app.
- `upstream/` in the release source archive: source archives named by the lockfile, with patches kept as separate files.

Native source code has not been edited for this app. `scripts/bootstrap.py` extracts the pinned runtime libraries, changes their Mach-O library IDs/dependency paths, and ad hoc signs the copies. `scripts/package.py` packages the application and re-signs the resulting bundle. Those exact modifications are documented in the scripts.

## Build the application

On an Apple Silicon Mac with macOS/Xcode 27.2 and Python 3, run:

```sh
python3 scripts/bootstrap.py
swift test
python3 scripts/package.py --output "dist/Video Player.app"
```

This route verifies the pinned Homebrew bottles before extracting their native runtime. It does not install or upgrade formulae. The resulting app does not need Homebrew installed to run.

## Rebuild native dependencies from source

Use the matching upstream archive, patches and recipe in this source bundle for each component. The recipes record `./configure`, Meson or CMake options and installation changes. Their declared general-purpose build tools (for example Clang/Xcode, make, CMake, Meson, Ninja, pkg-config and Python) must be available. macOS system libraries/frameworks and unmodified general-purpose build tools are not included in this archive.

Unpack sources into separate directories. Stage named resources where the recipe's `install` method places them; apply external patches and any `patch :DATA` block before the recorded build commands. The GLib patch contains `@@HOMEBREW_PREFIX@@`, which Homebrew substitutes with its install prefix. Preserve recipe `inreplace` changes and configure options. Header-only FastFloat/Vulkan sources and shaderc's pinned glslang/SPIRV resources are included. Build into a separate prefix in dependency order, without replacing system libraries.

The captured recipes provide the original Homebrew build instructions; this does not promise byte-identical compiler output on another toolchain. To substitute rebuilt libraries, populate `Vendor/lib` and `Vendor/include/mpv`, retain notices, then package with the script. The app uses dynamic libraries and no App Sandbox or DRM restriction prevents a user from replacing/re-signing their own copy. Modified libraries may require an ABI-compatible build or a corresponding application rebuild.

Homebrew recipes and patches are covered by the included Homebrew license. PotPlayer's Windows files and skins are research material and are excluded from every release asset and source archive.
