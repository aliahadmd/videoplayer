# Video Player 0.1.0 completion audit

Verified on 11 November 2026 on this Apple Silicon Mac, macOS 27.2 (26B123), Xcode 27.2, Swift 6.4.2. This records the local 0.1.0 deliverable and its subsequent GitHub release preparation. The earlier research's future hardware, notarization and clean-machine gates are not represented as completed.

## Deliverables

- Installed application: `~/Applications/Video Player.app`.
- Optimized, ad hoc signed bundle: `dist/Video Player 0.1.0/Video Player.app`.
- Application ZIP and application-source ZIP in `dist/`, with SHA-256 checksums.
- Source, build/verification scripts, usage guide, architecture notes, dependency manifest, notices, and the PotPlayer research reports.

The public GitHub release uses the separately packaged `dist/public/Video Player.app` and the checked assets under `dist/github`. It adds upstream notice files, an application-source archive from the release commit, and a third-party-source archive containing all 42 native components plus required header/build resources and patches. See [release notes](releases/v0.1.0.md) and [source availability](../ThirdParty/README.md).

The application is an original native Swift/AppKit/SwiftUI implementation using libmpv, FFmpeg, and libass. No proprietary PotPlayer program code, skins, or artwork are included in the app or source archive.

## Evidence

| Capability | Verification |
|---|---|
| Native embedded playback and teardown | Actual render context, advancing decoder, resize and normal termination in the release app |
| Broad local media | H.264/AAC, multi-audio MKV, VP9, AV1, HEVC 10-bit PQ and FLAC generated fixtures |
| Transport precision | Exact seeking, forward/backward frame stepping, speed readback and real A–B repeat |
| Subtitle/audio controls | External ASS, automatic SRT, secondary tracks, embedded ASS, audio switching, and timing readback from the engine |
| Screenshots and image controls | Decoded 1280×720 PNG with varied image data; brightness and reset readback |
| Queue and persistence | Automatic next, 30 rapid selections, subtitle association on append, resume position/timing, bounded history model, disabling history |
| Networking | HTTP byte-range seeking, trusted HTTPS playback, enabled peer verification and self-signed certificate rejection |
| Mac integration | Display-sleep assertion released on pause, Now Playing timeline follows paused seeking, compact floating window and restoration |
| Standalone packaging | 50 bundled libraries observed in-process, no Homebrew library loaded; `/opt/homebrew` reads denied during the test |
| Native UI | Accessibility/screenshot inspection of file opening, seeking, inspector, subtitle numeric entry, command search, full screen, settings, shortcut conflicts, saved queue reopening and quitting |
| Installed copy | Launched `~/Applications/Video Player.app` through the native app interface; the ready window, menus and transport appeared correctly |

The final optimized application passed **69 real playback assertions**. The separate Swift Testing run passed **13 model tests**, including parameterized time inputs. The authoritative individual playback checks and timestamp are in [validation/playback.json](validation/playback.json).

Build/test logs are retained locally in `.build/verification/`. Package validation uses strict deep code-signature verification and checks native-library dependency paths. The machine-readable release manifest records file sizes and SHA-256 checksums.

## Supported release and remaining limits

- Apple Silicon, macOS 27.2 or later. Intel and earlier macOS versions are not supported by this dependency bundle.
- OpenGL presentation; HDR input is tone mapped to SDR. Native HDR and system Picture in Picture remain future work. Compact floating mode is available.
- The bundle is ad hoc signed. It has not been Developer ID signed, notarized, submitted to the App Store, or validated on a clean second Mac. The initial public release states these limits. No updater service is included.
- Hardware-specific sleep/wake, Bluetooth route changes, external-display color behavior, physical VoiceOver use, sustained long-play/energy benchmarks, and exhaustive unusual media formats remain unverified. Accessibility labels and keyboard workflows were inspected; this does not establish full accessibility conformance.
- Protected streaming services, online subtitle accounts, translation/transcription, capture, plugin loading, and PotPlayer skin compatibility are outside this release.
- The original local source ZIP contained application source and dependency locations only. It is superseded for public distribution by the paired application-source and third-party-source archives attached to the GitHub release. These include upstream source archives, resource sources, external patches, original recipes and notices.

The local player is ready for everyday use within these limits. The usage guide describes shortcuts, precise controls, local data storage and reset behavior.
