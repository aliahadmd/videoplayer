# Usage

## Open and organize

Use File → Open File (⌘O), Open Folder (⌘⇧O), or Open URL (⌘L). Opening multiple files creates a queue. Open Folder adds a persistent root to the Library and displays its folder hierarchy. Add to Queue (⌘⇧A) appends files. Dropping a subtitle while a video is open attaches it to that video.

## Folder library

Show or hide Library with **⌘⇧L**, or use the sidebar toolbar button. Add as many root folders as you need with Open Folder. The app reads media in place without copying it. Each root contains expandable subfolders and supported video/audio files, with folders first and episode numbers in natural order. Empty folders remain visible. Hidden files, application packages, and symbolic links are excluded from child listings so browsing cannot follow loops or wander into another folder through a link.

Expand a folder to see its contents. Subfolders load in the background as needed. Click a video to play it; its immediate media siblings become the playback queue. Browsing or adding a folder leaves the current video alone. With the tree focused, arrow keys navigate/expand/collapse and Return opens the selected video or toggles a folder. Space still pauses playback.

For a single folder with more than 10,000 media files, the playback queue contains a 10,000-item window around your selected video and shows a message. The Library still displays all files; this limit keeps session saves bounded and responsive.

Use a root's context menu for Refresh Folder, Locate Folder, Show in Finder, or Remove from Library. Refresh and app activation discover changes on disk; folders are checked again at startup. A disconnected or unreadable root stays in your Library and offers Refresh/Locate Root. Locate preserves its identity and expanded subfolders and updates queued paths beneath it. **Remove from Library only forgets the shortcut; it never deletes files.**

## Automatic saving and restoration

Library roots, expanded branches, queue order/selection/repeat and open sidebars save locally when changed. Playback checkpoints save about every five seconds and on pause, seeks, window closing, app deactivation, sleep notification and clean quit. Writes run off the UI thread, replace the state atomically, synchronize the saved file, and retain a previous valid backup. The Library footer reports saving failures and offers Retry.

After relaunch or a normal computer restart, the library/queue return and the last local video opens **paused**. Position, speed and timing are restored; very recent power-loss changes may not have reached storage. Network sources remain in the queue and require Play to connect again. An unavailable file does not erase your queue. A valid backup recovers an unreadable primary state; future-version state is preserved instead of overwritten.

Settings → General → Library and session controls whether folders, queue and panels are remembered. Playback position follows Keep local playback history and Resume unfinished files. Disabling history removes saved positions without forgetting your explicitly saved Library; disabling session saving clears the saved workspace and its backup. Preferences, history and `workspace.json` live in `~/Library/Application Support/VideoPlayer`.

Show Queue with ⌘⇧P. Select a row to play it; its context menu provides move up/down, remove, and Show in Finder. Save Queue (⌘⇧E) writes a `.vpqueue` document containing media addresses. Reopen it through Open File. Saved queues do not copy the underlying media.

## Playback

| Default shortcut | Action |
|---|---|
| Space | Play/pause |
| ← / → | Seek by the interval selected in Settings |
| ⇧← / ⇧→ | Seek one minute |
| ⌘← / ⌘→ | Previous/next file |
| , / . | Previous/next frame |
| [ / ] | Decrease/increase speed |
| Backspace | Restore normal speed |
| ↑ / ↓ | Volume |
| M | Mute |
| A / B / ⇧B | Set loop start/end/clear |
| Z / X | Subtitles 0.1 seconds earlier/later |
| ⇧Z / ⇧X | Audio 0.1 seconds earlier/later |
| ⌘J | Go to a time |
| ⌘S | Save a screenshot |
| ⌃⌘F | Full screen |
| ⌘T | Float on top |
| ⌘⇧M | Compact floating player |
| ⌘I | Inspector |
| ⌘⇧K | Find command |

Playback keys are suppressed while editing text. Standard editing actions are in the Edit menu. Settings → Shortcuts validates conflicts and reserves standard Mac editing/window commands. Blank bindings disable a shortcut.

## Inspector

Play contains speed, frame stepping, exact time navigation, A–B points, and chapters. A loop end must follow its start. Live media may not support seeking or a known duration.

Subs selects primary/secondary tracks and controls timing, scale, and placement. Positive subtitle delay displays text later. ASS content keeps its authored styling. Audio selects tracks/output devices and adjusts A/V delay. Automatic output follows system selection.

Video contains reversible geometry/image adjustments and deinterlacing. Reset Current File Adjustments also clears speed/timing/A–B changes. Volume, font defaults, history preferences, and appearance remain global. Info shows source and playback diagnostics; HDR metadata does not mean HDR output in this version.

## Resume and privacy

Settings controls local history and unfinished-file resume. History is bounded to 200 local files and can be cleared. A resumed file shows Start Over. History/preferences live in `~/Library/Application Support/VideoPlayer`; no account or telemetry service is required.

An unavailable drive or damaged file produces an inline error. The queue remains available. A screenshot success message appears after the engine confirms writing it.
