# PotPlayer: product, implementation and extensibility evidence

Researched 2026-11-09. This appendix studies the Windows product; the main report translates the findings into a Mac product.

## Evidence boundary

The investigation used the official site, its current changelog, Kakao's launch announcement, and a downloaded official x64 installer. The installer was **not executed**. Selected files were extracted as data; REA 6.8.0 parsed PE imports, exports and resources. No functions were decompiled. UI findings below come from shipped skin definitions, artwork, menu/configuration strings and documentation, **not hands-on Windows usability or playback testing**.

Official package identity:

- [Official x64 installer](https://t1.kakaocdn.net/potplayer/PotPlayer/Version/Latest/PotPlayerSetup64.exe), downloaded 2026-11-09; 51,257,600 bytes; installer version `26.10.21.0`, product version `1.7.23159.0`; server Last-Modified 2026-11-02.
- Installer SHA-256: `71374ce7f60136b8e8dd1618f736d37ccbefcc5875feb33650f9f8de0bba87e8`.
- Main `PotPlayer64.dll`: 35,303,968 bytes; SHA-256 `b72fdfe269df2062502897e752a0e83a5db938975a62d8f31d441f7d3e83461e`.
- Retained [inventory](artifacts/installer-inventory.txt), [static summary](artifacts/static-evidence-summary.json), [REA imports](artifacts/player-pe-imports.json), [REA resources](artifacts/player-pe-resources.json) and [FFmpeg-module exports](artifacts/ffcodec-exports.json). The `Latest` URL is mutable: hashes identify the inspected build.

## What the product is

PotPlayer is Kakao's proprietary, free-to-use Windows media player. The [official site](https://potplayer.tv/) offers x86, x64 and Windows ARM64 builds, lists Windows 7–11, and advertises hardware decoding, multiple subtitle systems, added codecs, scene previews/bookmarks and disc/device playback. These are vendor claims, not benchmark results. The [EULA](https://potplayer.tv/publicRelation) retains company ownership; freeware does not mean an open-source application. The package's component notices separately acknowledge open-source dependencies.

Its history explains its breadth. Kakao's [2007 launch announcement](https://www.kakaocorp.com/page/detail/6050) introduced PotPlayer alongside Daum Live Pot, combining viewing and personal broadcasting with chat, timeshift and variable speed. It evolved from a broadcast-platform client as well as a local player. This should inform scope: recreating every historical service feature is unnecessary for a Mac local-media player.

### Current versus historical features

The [official changelog](https://t1.kakaocdn.net/potplayer/PotPlayer/v4/Update2/UpdateEng.html) is more current than the marketing page. Relevant changes: 2026-10-21 selects D3D11 video/WASAPI audio defaults and adds ReplayGain; 2026-08-19 introduces Windows ARM64; 2026-06-22 removes Kakao TV; 2026-04-01 expands libass output and internal HLS/DASH handling. Earlier releases add real-time Whisper subtitles, HDR tone-map selection, subtitle translation and AngelScript extensions. Compatibility fixes span container parsing, GPU decoding, seeking, subtitle rendering and A/V sync. This is evidence of sustained maintenance, not evidence of the team's test process or staffing.

**Resource trap:** the inspected current package still ships broadcast/chat labels, sprites and command IDs. Their presence does not prove those services still work. Likewise, a translated menu label is weaker evidence than a tested feature.

## How it was built: observations and confidence

| Layer | Evidence | Conclusion and confidence |
|---|---|---|
| Native application | Main library is x64 PE32+; Windows DLL imports and native resource tables are present. | Native Windows implementation: verified. This is not an Electron package. |
| C++/MFC UI framework | Main library contains MSVC-style C++ RTTI for `CWinApp`, `CWnd`, `CMFCDynamicLayout`, plus 90 `AFX_DIALOG_LAYOUT` resources and 187 dialog resources. | C++/MFC usage: high-confidence inference from several independent binary indicators. It does not reveal the language of every component. [Microsoft describes MFC](https://learn.microsoft.com/en-us/cpp/mfc/general-mfc-topics?view=msvc-160) as its C++ Windows framework. |
| Custom presentation | `Default.dsf` is a ZIP containing XML-like layout files, includes, localized string tables and bitmap atlases. Layout elements bind buttons/sliders/labels to command IDs. | A custom skin/layout layer over the native app is verified; the media surface and surrounding UI have separate declarations. |
| Media/filter architecture | Native RTTI includes `CBaseFilter`, `CBaseInputPin`, `CBaseRenderer`; menu resources expose source/splitter/decoder/renderer controls. | DirectShow-style filter architecture is strongly supported. Exact graph construction, ownership, scheduling and fallback policies remain unobserved. |
| Codec stack | Component notice credits FFmpeg; `ffcodec64.dll` exports codec, format and filter functions. | FFmpeg is genuinely part of the shipped media stack, not merely mentioned in documentation. Do not infer its exact configuration or all patched behavior. |
| Output/GPU | D3D11/WASAPI defaults are documented in the changelog; package includes Direct3D shader source and compiler DLL. | Windows-specific decoding/output infrastructure. Translating the product to macOS means choosing a new platform integration, not reusing these APIs. |
| Supporting modules | Package includes separate MediaInfo, QuickSync, BASS and Whisper components. License notice also names SQLite, AngelScript, JsonCpp, FreeType, compression/image libraries and whisper/llama. | A modular collection of native libraries plus proprietary application logic. Presence/credit does not establish which component handles every format. |
| Installer | NSIS metadata and the component notice agree. | NSIS installer: verified. The 32-bit installer stub is separate from its x64 app payload. |

Primary local sources: [component notice](artifacts/potplayer-extracted/License.txt), [skin directory](artifacts/default-skin/VideoSkin.xml), [English resource strings](artifacts/potplayer-extracted/Language/English.ini), [shader example](artifacts/potplayer-extracted/PxShader/Sharpen.txt). PE type-name offsets and resource counts are retained in the static summary.

REA evidence IDs: imports `ev_ea54787fe9c4bf1b0c863110ecd813f5a72b564aada132622357ef522c74af48`; resources `ev_adf902ad2a42216e07b61af746e7f7437fcea1d7da076c1039bd8946056c811c`; codec exports `ev_5e64180c1763b1d50da0992ec7966de61c387b17ebd0310592a6571ee9079ae1`. These static records do not observe execution; dynamically loaded APIs can escape import tables.

## UI/UX structure recovered from the default skin

The [desktop sprite atlas](artifacts/default-skin/Main.png) shows a dark charcoal base, small monochrome transport icons and yellow highlights. It is an asset sheet, **not a screenshot**. [Control artwork](artifacts/default-skin/Control.png), [playlist artwork](artifacts/default-skin/PlayList.png) and a [touch variant](artifacts/default-skin/TouchMain.png) are retained for inspection, not reuse in a new product.

The recovered hierarchy is:

1. **Video first:** the central client region holds the video; separate skin definitions cover ordinary video, audio, compact audio, DVD and device modes.
2. **Window controls and identity:** a narrow title strip provides the app menu, title/status and window actions, including an always-on-top cycle.
3. **Playback controls:** a bottom seek bar and volume/mute sit beside transport/open controls and elapsed/total time. Playlist and control-panel toggles expose more tools.
4. **Conditional technical status:** hardware/software decoding, HDR, codec and channel badges appear based on playback state and available width. The skin's width conditions confirm deliberate density management.
5. **More depth on demand:** a separate panel groups subtitle, image, transport and audio controls. Extensive pop-up menus and preferences expose deeper settings.

Sources: [VideoSkin.xml](artifacts/default-skin/VideoSkin.xml), [top strip](artifacts/default-skin/TopCommon.txt), [bottom controls](artifacts/default-skin/BottomVideo.txt), [panel definitions](artifacts/default-skin/SubCommon.txt), [simple menu](artifacts/potplayer-extracted/Menus/SimpleMenu.xml). These files declare visibility/layout; whether a particular control is reachable in each current mode was not tested.

### Interaction and feature matrix

| Capability | Primary evidence | Product lesson for a Mac player |
|---|---|---|
| Immediate playback | Skin binds file open, play/pause, timeline and volume controls. | Make open/drop/play effortless; retain keyboard access. |
| Precise navigation | Menu/config resources include frame/keyframe stepping, configurable seek intervals, exact-time entry, chapter/bookmark and scene browsers. | Support both quick seeks and precise inspection; label their different cost/accuracy. |
| Repeat and learning | Panel declares A/B endpoints and speed control; resource strings include subtitle/marked-section loops. | A/B repeat and speed belong in the early power-user feature set. |
| Subtitle control | Panel declares font/size/position/track/sync actions; resources include multiple subtitle/translation options. | Subtitle selection and delay must be easily discoverable. Complex ASS rendering belongs in the engine. |
| Playlist and continuity | Resources expose albums, queues, favorites, saved playlists and playback-position preferences. | Distinguish a temporary queue from saved collections and remember progress predictably. |
| Image/audio adjustments | Panel binds color, aspect, screenshot, track and sound controls; shader files and deeper settings are present. | Put common adjustments in a coherent inspector; defer specialist filters. |
| Input customization | Configuration declares user hotkey overrides, global/media keys and modifier+mouse actions. | Provide sensible Mac defaults and a searchable remapping screen. |
| Network and device opening | Resources list URLs, FTP/WebDAV/HTTP, external audio/subtitles, optical discs and capture sources. | Prioritize local files and ordinary URLs first; treat each extra source as its own integration. |

The first six rows are grounded in multiple layout/menu definitions. Broader source/device availability remains resource- and vendor-documented rather than runtime-verified. Shortcut defaults appearing in [English.ini](artifacts/potplayer-extracted/Language/English.ini) include Space playback, left/right seeks, D/F frame stepping and F5 preferences. These establish the power-user model; a Mac implementation should choose deliberate platform-appropriate bindings.

**Design assessment (inference):** the strength is compact access to extensive controls, with a common command vocabulary across skins, menus and hotkeys. The probable cost is discovery and cognitive load: dense menus, small icon targets, multiple modes and overlapping configuration routes. This is an inspection-based assessment, not a measured usability finding. For the Mac version, keep the depth but supply a clear menu bar, accessible controls, searchable commands and progressive disclosure.

## Developer experience: what is actually exposed

The proprietary application's internal DX is not public. Nothing reviewed establishes its repository layout, IDE version, build system, unit/integration tests, continuous integration, branching policy or release team size. Linker metadata is not proof of a particular Visual Studio workflow.

There is, however, a real **extension-author experience**:

- [Extension/api.txt](artifacts/potplayer-extracted/Extension/api.txt) documents an AngelScript host interface, API-version queries, a debug console/logging, HTTP requests, files, JSON/regex helpers, background threads and synchronization. It documents constraints on configuration-file writes and script timeouts; those declarations were not security-tested.
- Shipped scripts implement subtitle search/translation and media URL parsing, including YouTube. They expose metadata/version callbacks and play-item parsing, making service-specific adaptation possible without recompiling the app.
- Script API documentation and working examples sit beside the installed application. This is useful for discoverability but weaker than a versioned public SDK, automated compatibility tests and a maintained extension template.
- Skin authors edit declarative files and sprite assets. Command IDs connect layout to existing player actions; skinning does not imply arbitrary access to the playback engine.
- [Command-line documentation](artifacts/potplayer-extracted/CmdLine64.txt) supports opening files/folders/URLs or stdin, selecting an instance, queueing, starting at a time and adding external tracks. This is a separate automation surface from scripting and skins.

Sources: installed API text, [YouTube parser example](artifacts/potplayer-extracted/Extension/Media/PlayParse/MediaPlayParse%20-%20YouTube.as), skin definitions and command-line help. The [official site](https://potplayer.tv/) lists an email contact and a social page; its HTML has an inactive forum link. That is not evidence about current response quality or community size.

## Reusable lessons and remaining unknowns

The important engineering pattern is a stable command/state layer shared by UI, keyboard, scripting and automation, wrapped around a maintained playback pipeline. The variety of rendering/codec/sync fixes shows why the Mac app should use a proven media engine and invest in integration, state management, accessibility and a representative media test corpus.

| Research question | Status |
|---|---|
| Supported platform, ownership, historical purpose, current release direction | Answered with primary sources. |
| Native versus web implementation, major libraries, custom skin format | Answered by package evidence; C++/MFC attribution is high confidence. |
| Full media graph and source/module boundaries | Partially answered; filter-style architecture supported, detailed internals not reconstructed. |
| Default UI hierarchy, customization and automation surfaces | Answered from resources; live behavior untested. |
| Actual usability, VoiceOver equivalence, battery use, A/V accuracy, HDR correctness | Unresolved; requires runtime testing on appropriate platforms. |
| PotPlayer internal build/test/release workflow | Unresolved; no authoritative public evidence found in reviewed sources. |

No proprietary code, skins, icons or branding should become the Mac app's implementation assets. The actionable reference is its feature model and interaction principles. License notices describe dependency obligations separately from the proprietary application; the Mac dependency selection needs its own verified build/license inventory.
