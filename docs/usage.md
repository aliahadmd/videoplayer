# Usage

## Open and organize

Use File → Open File (⌘O), Open Folder (⌘⇧O), or Open URL (⌘L). Opening multiple files creates a queue. Folder opening scans immediate media files and sorts episode numbers naturally. Add to Queue (⌘⇧A) appends items. Dropping a subtitle while a video is open attaches it to that video.

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
