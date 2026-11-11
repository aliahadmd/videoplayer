# Persistent folder library — 0.2.0

The folder browser stays separate from the ordered playback queue. Opening a folder adds a saved Library root and leaves playback undisturbed. Expanding reads one directory; selecting a video plays its immediate media siblings as a queue. Folder names and paths remain hierarchical instead of flattening a drive into thousands of entries.

The implementation uses a stable root UUID, relative node paths, saved disclosure state and security-scoped bookmarks. Root relocation keeps that identity and remaps queued media underneath it. Missing roots remain visible until explicitly removed. Remove from Library has no filesystem-delete operation.

Autosave uses versioned local JSON, a serial writer, monotonic revision checks, atomic replacement, file synchronization and a previous valid backup. Changes save without waiting for quit. Playback checkpoints run approximately every five seconds and on pause, seek/restart, deactivation, window close, sleep notification and shutdown. Startup restores paused, and keeps the old checkpoint until the restored seek is acknowledged. An abrupt machine failure can still lose the newest changes; no absolute power-loss guarantee is made.

The browser uses native disclosure/selection behavior and supports arrow navigation and Return. Filesystem reads are serialized away from the UI, with lazy child listings, cancellation and stale-result rejection. Refresh runs on startup and periodically on app activation; users can explicitly refresh any root. There is no thumbnail crawl or recursive whole-drive index.

Privacy controls distinguish saved folder shortcuts/queue from playback history. Positions follow history/resume preferences; session saving can be disabled separately. Turning either off sanitizes the relevant saved state and backup. External drives do not cause saved entries to be silently discarded.

Implementation references: Apple's [bookmark API](https://developer.apple.com/documentation/foundation/url/bookmarkdata(options:includingresourcevaluesforkeys:relativeto:)), [shallow directory enumeration](https://developer.apple.com/documentation/foundation/filemanager/contentsofdirectory(at:includingpropertiesforkeys:options:)), and [controlled disclosure groups](https://developer.apple.com/documentation/swiftui/disclosuregroup).

Verification includes model tests for hierarchy/sorting/link avoidance, preference migration, corrupted-state recovery, future-version preservation and stale-write rejection. The native test starts separate processes, saves a nested video at 2.25 seconds, restores it paused, saves a later checkpoint, kills the process without shutdown, and verifies recovery in another launch. UI inspection covers deep playback, disclosure controls, native folder selection, light/dark appearance, hiding/reopening the sidebar and keyboard navigation.
