# Architecture

`PlayerCore` holds the Foundation-only model: queue identity/order/repeat, shortcut definitions/conflicts, time parsing, playlists, and bounded resume persistence. Swift Testing covers boundary and failure cases.

Folder browsing is a separate model from the playback queue. `LibraryLocation` identifies each entry by root UUID and relative path. A root keeps a security-scoped bookmark and expanded relative paths. `FolderLibrary` owns cached shallow listings; `FolderScanner` serializes filesystem reads away from the UI, cancels obsolete requests and rejects stale generations after refresh/remove/relink. Symbolic links, hidden files and packages are excluded from child listings. SwiftUI's controlled disclosure groups preserve the hierarchy and expansion state; focused native lists receive navigation keys before global playback shortcuts.

`WorkspaceState` records roots, queue, current item, playback checkpoint and panel state. A versioned `WorkspaceStore` validates documents, writes atomically with file synchronization and a valid backup, recovers a damaged primary, and preserves newer-version documents. `WorkspaceWriter` serializes writes and rejects stale revisions. Structural changes save immediately; playback saves about every five seconds and at lifecycle boundaries. Startup restores local media paused, preserves the old checkpoint until the restored seek completes, and never automatically reconnects network URLs. Clean quit flushes the final snapshot from a detached lifetime task so AppKit's termination run loop cannot starve a main-actor continuation.

`PlayerSession` is the main-actor observable coordinator. It owns session state, commands, native panels, preferences/history, and media controls. Global engine properties (pause, volume, mute and audio devices) survive file changes. Start/end events are correlated with entry/item identities so a stopped old item cannot advance the current queue.

`PlaybackEngine` wraps libmpv. The C handle is thread-safe; application control/event access uses a dedicated serial queue and asynchronous commands. Borrowed event/node data is converted into Sendable values before delivery to the main actor. A periodic nonblocking drain avoids retaining a destroyed callback owner.

`GLRenderer` owns the public OpenGL render context and an independent serial rendering queue. The context is made current and locked for operations. Rendering is stopped/freed before engine destruction; AppKit retains the underlying NSOpenGLContext. This does not claim a Metal render API or native HDR output.

The AppKit delegate owns the native window, menus/toolbar and keyboard monitor. A handled key is consumed once. Editors use the standard responder chain. Discrete commands ignore auto-repeat; incremental controls may repeat. SwiftUI presents transport, queue, inspectors, command search, and settings. The native video view survives state updates; compact mode adapts transport layout.

Shutdown saves local state, releases system controls/sleep assertions/security-scoped access, stops rendering, and asynchronously destroys the engine. Its final AppKit reply uses the main run loop so a nested termination loop cannot starve it.

The bootstrap verifies pinned archives, extracts licenses/recipes, rewrites dylib paths to sibling libraries, and signs local copies. Packaging removes the development rpath and verifies paths/signatures. It does not publish or change default file associations.

The QA app has a distinct identifier and isolated data. Its opt-in `PlaybackSelfTest` drives the actual session/engine/surface. The same opt-in test can run inside the final bundle with isolated data. `scripts/verify.py` adds loopback HTTP/untrusted HTTPS and checks loaded library locations; it is not a simulated playback backend.

TLS peer verification is explicitly enabled. The OpenSSL dependency uses `/etc/ssl/cert.pem`, avoiding a dependency on the Homebrew installation's CA path. This uses mpv's documented [TLS verification and CA options](https://mpv.io/manual/stable/#options-tls-verify). Custom certificates installed only in a user's Keychain are not imported into this PEM file by the app.
