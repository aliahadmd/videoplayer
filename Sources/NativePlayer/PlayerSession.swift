import AppKit
import Observation
import MediaPlayer
import IOKit.pwr_mgt
import PlayerCore
import UniformTypeIdentifiers
import os

struct MediaTrack: Identifiable {
    let id: Int
    let type: String
    let title: String
    let language: String
    let codec: String
    var label: String { [title.isEmpty ? "Track \(id)" : title, language, codec].filter { !$0.isEmpty }.joined(separator: " · ") }
}
struct Chapter: Identifiable { let id: Int; let title: String; let time: Double }

@Observable final class PlayerSession {
    var queue = PlaybackQueue()
    var currentItem: MediaItem?
    var values: [String: EngineValue] = [:]
    var loaded = false
    var phase = "Ready"
    var errorMessage: String?
    var notice: String?
    private enum Sidebar { case queue, inspector }
    private var sidebar: Sidebar?
    var showQueue: Bool {
        get { sidebar == .queue }
        set { if newValue { sidebar = .queue } else if sidebar == .queue { sidebar = nil } }
    }
    var showInspector: Bool {
        get { sidebar == .inspector }
        set { if newValue { sidebar = .inspector } else if sidebar == .inspector { sidebar = nil } }
    }
    var showCommands = false
    var showJump = false
    var floating = false
    var compact = false
    private var normalFrame: NSRect?
    private var normalFloating = false
    var preferences: Preferences
    var history: [ResumeRecord]
    var engine: PlaybackEngine?
    var renderer: GLRenderer?
    weak var window: NSWindow?
    var settingsAction: (() -> Void)?
    var bindingsChanged: (() -> Void)?
    private let store: DiskStore
    private var activeEntry: Int64?
    private var activeLoadID: UUID?
    private var currentLoadID = UUID()
    private var registeredItems: [Int64: UUID] = [:]
    private var deferredLoadedEntry: Int64?
    private var pendingRestore: ResumeRecord?
    private var openTask: Task<Void, Never>?
    private var scopes: [URL] = []
    private var lastHistoryWrite = Date.distantPast
    private var lastSystemPlaybackUpdate = Date.distantPast
    private var powerAssertion: IOPMAssertionID = 0
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private var openingID = UUID()
    var playbackRevision = 0
    var preventsDisplaySleep: Bool { powerAssertion != 0 }
    private let globalProperties: Set<String> = ["pause", "volume", "mute", "audio-device-list", "audio-device"]

    init(directory: URL? = nil) {
        let directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VideoPlayer")
        store = DiskStore(directory: directory)
        preferences = store.read(Preferences.self, name: "preferences.json") ?? Preferences()
        history = store.read([ResumeRecord].self, name: "history.json") ?? []
        if !preferences.rememberHistory { history = [] }
        do {
            engine = try PlaybackEngine { [weak self] events in
                DispatchQueue.main.async { self?.receive(events) }
            }
            applyPreferences()
        } catch { errorMessage = error.localizedDescription }
        configureRemoteControls()
    }
    var position: Double { finite("time-pos") }
    var duration: Double { finite("duration") }
    var paused: Bool { values["pause"]?.flag ?? true }
    var playing: Bool { loaded && !paused }
    var volume: Double { values["volume"]?.number ?? preferences.volume }
    var speed: Double { values["speed"]?.number ?? 1 }
    var muted: Bool { values["mute"]?.flag ?? false }
    var seekable: Bool { values["seekable"]?.flag ?? false }
    var subtitleDelay: Double { finite("sub-delay") }
    var audioDelay: Double { finite("audio-delay") }
    var tracks: [MediaTrack] { (values["track-list"]?.array ?? []).map { MediaTrack(id: Int($0["id"].number), type: $0["type"].string, title: $0["title"].string, language: $0["lang"].string, codec: $0["codec"].string) } }
    var chapters: [Chapter] { (values["chapter-list"]?.array ?? []).enumerated().map { Chapter(id: $0.offset, title: $0.element["title"].string.isEmpty ? "Chapter \($0.offset + 1)" : $0.element["title"].string, time: $0.element["time"].number) } }
    func finite(_ key: String) -> Double { let value = values[key]?.number ?? 0; return value.isFinite ? value : 0 }
    func shortcut(_ command: PlayerCommand) -> String { Shortcut(preferences.shortcuts[command.rawValue] ?? command.defaultShortcut)?.display ?? "" }

    func applyPreferences() {
        engine?.set("volume", min(100, max(0, preferences.volume)))
        engine?.set("hwdec", preferences.hardwareDecoding ? "videotoolbox" : "no")
        engine?.set("sub-font", preferences.subtitleFont)
        engine?.set("sub-font-size", preferences.subtitleSize)
        NSApp.appearance = switch preferences.appearance { case "dark": NSAppearance(named: .darkAqua); case "light": NSAppearance(named: .aqua); default: nil }
    }
    func savePreferences() {
        if !preferences.rememberHistory { clearHistory() }
        do { try store.write(preferences, name: "preferences.json") }
        catch { errorMessage = "Could not save preferences: \(error.localizedDescription)" }
    }
    func applyPreferenceChanges(from previous: Preferences) {
        if previous.hardwareDecoding != preferences.hardwareDecoding { engine?.set("hwdec", preferences.hardwareDecoding ? "videotoolbox" : "no") }
        if previous.subtitleFont != preferences.subtitleFont { engine?.set("sub-font", preferences.subtitleFont) }
        if previous.subtitleSize != preferences.subtitleSize { engine?.set("sub-font-size", preferences.subtitleSize) }
        if previous.appearance != preferences.appearance {
            NSApp.appearance = switch preferences.appearance { case "dark": NSAppearance(named: .darkAqua); case "light": NSAppearance(named: .aqua); default: nil }
        }
    }
    func clearHistory() {
        history = []
        do { try store.write(history, name: "history.json") }
        catch { errorMessage = "Could not clear history: \(error.localizedDescription)" }
        NSDocumentController.shared.clearRecentDocuments(nil)
    }
    func openPanel(folder: Bool = false, append: Bool = false, subtitle: Bool = false) {
        window?.makeKeyAndOrderFront(nil)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = folder
        panel.canChooseFiles = !folder
        panel.allowsMultipleSelection = !subtitle
        panel.message = subtitle ? "Choose a subtitle file to attach to the current video." : "Choose media files. Folders use natural file ordering."
        panel.prompt = append ? "Add" : "Open"
        guard panel.runModal() == .OK else { return }
        if subtitle { panel.urls.forEach(attachSubtitle) } else { open(panel.urls, append: append) }
    }
    func openURL() {
        let alert = NSAlert(); alert.messageText = "Open Media URL"; alert.informativeText = "Enter a direct HTTP, HTTPS, RTSP, or RTMP media address."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24)); field.placeholderString = "https://example.com/video.mp4"
        alert.accessoryView = field; alert.addButton(withTitle: "Open"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let url = URL(string: field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)), ["http", "https", "rtsp", "rtmp"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { errorMessage = "Enter a valid direct media URL."; return }
        open([url])
    }
    func open(_ urls: [URL], append: Bool = false) {
        guard !urls.isEmpty else { return }
        window?.makeKeyAndOrderFront(nil)
        if urls.allSatisfy(MediaFiles.isSubtitle) { urls.forEach(attachSubtitle); return }
        openTask?.cancel()
        let request = UUID(); openingID = request
        for url in urls where url.isFileURL { if url.startAccessingSecurityScopedResource() { scopes.append(url) } }
        openTask = Task { [weak self] in
            do {
                let expanded = try await MediaFiles.expand(urls)
                guard !Task.isCancelled, let self, self.openingID == request else { return }
                let subtitles = expanded.filter(MediaFiles.isSubtitle)
                let items = expanded.filter { !MediaFiles.isSubtitle($0) }.map { url in MediaItem(url: url, bookmark: url.isFileURL ? try? url.bookmarkData(options: .withSecurityScope) : nil) }
                guard !items.isEmpty else { self.errorMessage = "No supported media files were found in this folder."; return }
                self.saveProgress()
                if !append { self.pendingSubtitles.removeAll() }
                if !subtitles.isEmpty { self.pendingSubtitles[items[0].id] = subtitles }
                if append {
                    let wasEmpty = self.queue.items.isEmpty
                    self.queue.append(items)
                    if wasEmpty { self.load(items[0]) }
                    self.showQueue = true
                } else { self.queue.replace(items); self.load(items[0]) }
                if items.count > 1 { self.showQueue = true }
            } catch is CancellationError {} catch { self?.errorMessage = "Could not open media: \(error.localizedDescription)" }
        }
    }
    private var pendingSubtitles: [UUID: [URL]] = [:]
    func openRecent(_ record: ResumeRecord) {
        var url = record.url
        if let bookmark = record.bookmark {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale) { url = resolved }
        }
        open([url])
    }
    func select(_ item: MediaItem) { saveProgress(); guard queue.select(item.id) else { return }; load(item) }
    private func load(_ item: MediaItem) {
        currentLoadID = UUID()
        currentItem = item; loaded = false; phase = "Opening…"; errorMessage = nil; notice = nil
        values = values.filter { globalProperties.contains($0.key) }
        pendingRestore = preferences.rememberHistory ? history.first { $0.url == item.url } : nil
        engine?.command(["loadfile", item.url.isFileURL ? item.url.path : item.url.absoluteString, "replace"], itemID: currentLoadID)
        engine?.set("pause", false)
        window?.title = item.title
    }
    func attachSubtitle(_ url: URL) {
        guard loaded else { errorMessage = "Open a video before adding subtitles."; return }
        guard MediaFiles.isSubtitle(url) else { errorMessage = "Choose an SRT, ASS, VTT, or another supported subtitle file."; return }
        if url.startAccessingSecurityScopedResource() { scopes.append(url) }
        engine?.command(["sub-add", url.path, "select"])
    }
    func remove(_ item: MediaItem) {
        let current = item.id == currentItem?.id
        if current { saveProgress() }
        queue.remove(item.id)
        pendingSubtitles.removeValue(forKey: item.id)
        if current { if let next = queue.current { load(next) } else { stop() } }
    }
    func next(automatic: Bool = false) { saveProgress(); if let item = queue.next(automatic: automatic) { load(item) } }
    func previous() { saveProgress(); if let item = queue.previous() { load(item) } }
    func stop() { saveProgress(); engine?.command(["stop"]); loaded = false; phase = "Stopped"; updateSystemPlayback() }
    func seek(_ seconds: Double) {
        guard loaded, seekable, seconds.isFinite else { return }
        engine?.command(["seek", String(max(0, min(seconds, duration > 0 ? duration : seconds))), "absolute+exact"])
    }
    func set(_ name: String, _ value: Double) {
        guard value.isFinite else { return }
        let value = PlaybackEngine.normalized(name, value)
        values[name] = .number(value)
        if name == "volume" { preferences.volume = value }
        engine?.set(name, value)
    }
    func set(_ name: String, _ value: Bool) { values[name] = .flag(value); engine?.set(name, value) }
    func set(_ name: String, _ value: String) { values[name] = .string(value); engine?.set(name, value) }
    func selectTrack(_ property: String, id: Int) { values[property] = .number(Double(id)); engine?.set(property, id == 0 ? "no" : String(id)) }
    func togglePause() { if loaded { set("pause", !paused); updateSystemPlayback() } else if let item = currentItem { load(item) } }

    func perform(_ command: PlayerCommand) {
        switch command {
        case .open: openPanel(); case .openFolder: openPanel(folder: true); case .openURL: openURL(); case .addFiles: openPanel(append: true); case .saveQueue: saveQueue(); case .attachSubtitle: openPanel(subtitle: true)
        case .toggleQueue: showQueue.toggle(); if showQueue { showInspector = false }
        case .toggleInspector: showInspector.toggle(); if showInspector { showQueue = false }
        case .commands: showCommands = true; case .jumpToTime: showJump = true
        case .fullscreen: window?.toggleFullScreen(nil)
        case .alwaysOnTop: floating.toggle(); window?.level = floating ? .floating : .normal
        case .compactPlayer: toggleCompact()
        case .togglePause: togglePause(); case .stop: stop(); case .previous: previous(); case .next: next()
        case .volumeUp: set("volume", min(100, volume + 5)); case .volumeDown: set("volume", max(0, volume - 5)); case .mute: set("mute", !muted)
        default:
            guard loaded else { return }
            switch command {
            case .backward: engine?.command(["seek", String(-preferences.seekSeconds), "relative+exact"])
            case .forward: engine?.command(["seek", String(preferences.seekSeconds), "relative+exact"])
            case .longBackward: engine?.command(["seek", "-60", "relative+exact"]); case .longForward: engine?.command(["seek", "60", "relative+exact"])
            case .frameForward: engine?.command(["frame-step"]); case .frameBackward: engine?.command(["frame-back-step"])
            case .speedUp: set("speed", min(4, speed + 0.1)); case .speedDown: set("speed", max(0.25, speed - 0.1)); case .normalSpeed: set("speed", 1)
            case .subtitleEarlier: set("sub-delay", subtitleDelay - 0.1); case .subtitleLater: set("sub-delay", subtitleDelay + 0.1)
            case .audioEarlier: set("audio-delay", audioDelay - 0.1); case .audioLater: set("audio-delay", audioDelay + 0.1)
            case .loopA: set("ab-loop-a", position); notice = "Loop starts at \(TimeText.string(position))"
            case .loopB:
                if case .number(let a) = values["ab-loop-a"], position > a { set("ab-loop-b", position) }
                else { errorMessage = "Set a loop start before the current position." }
            case .clearLoop: engine?.set("ab-loop-a", "no"); engine?.set("ab-loop-b", "no")
            case .screenshot: screenshot()
            case .resetAdjustments: resetAdjustments()
            default: break
            }
        }
    }
    func saveQueue() {
        guard !queue.items.isEmpty else { errorMessage = "Add media files before saving a queue."; return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Watch queue.vpqueue"
        panel.allowedContentTypes = [UTType(exportedAs: "com.aliahad.videoplayer.queue", conformingTo: .json)]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Playlist.encode(queue.items.map(\.url)).write(to: url, options: .atomic); notice = "Queue saved" }
        catch { errorMessage = error.localizedDescription }
    }
    private func toggleCompact() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        if compact {
            compact = false; window.minSize = NSSize(width: 720, height: 480)
            if let frame = normalFrame { window.setFrame(frame, display: true) }
            floating = normalFloating; window.level = floating ? .floating : .normal
        } else {
            normalFrame = window.frame; normalFloating = floating
            compact = true; floating = true; showQueue = false; showInspector = false
            window.minSize = NSSize(width: 320, height: 220)
            window.setContentSize(NSSize(width: 480, height: 300)); window.level = .floating
        }
    }
    func resetAdjustments() {
        for property in ["brightness", "contrast", "saturation", "gamma", "video-zoom", "video-pan-x", "video-pan-y", "video-rotate", "sub-delay", "audio-delay"] { set(property, 0) }
        set("speed", 1); set("sub-scale", 1); set("sub-pos", 100); set("video-aspect-override", -1)
        engine?.set("deinterlace", false); engine?.set("ab-loop-a", "no"); engine?.set("ab-loop-b", "no")
        notice = "Current file adjustments reset"
    }
    func screenshot() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(currentItem?.url.deletingPathExtension().lastPathComponent ?? "Frame")-\(Int(position)).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        engine?.command(["screenshot-to-file", url.path, "subtitles"])
        notice = "Saving screenshot…"
    }
    private func receive(_ events: [EngineEvent]) {
        for event in events {
            switch event {
            case let .registered(id, itemID):
                registeredItems[id] = itemID
                if registeredItems.count > 256 { for old in registeredItems.keys.sorted().prefix(registeredItems.count - 256) { registeredItems.removeValue(forKey: old) } }
                if activeEntry == id {
                    activeLoadID = itemID
                    if deferredLoadedEntry == id, itemID == currentLoadID { finishLoading() }
                }
            case let .started(id):
                activeEntry = id
                activeLoadID = registeredItems[id]
                deferredLoadedEntry = nil
            case let .property(name, value):
                guard activeLoadID == currentLoadID || globalProperties.contains(name) else { continue }
                updateProperty(name, value)
            case let .refreshed(itemID, name, value):
                guard itemID == currentLoadID, loaded else { continue }
                updateProperty(name, value)
            case .loaded:
                guard activeLoadID == currentLoadID else { if activeLoadID == nil { deferredLoadedEntry = activeEntry }; continue }
                finishLoading()
            case let .loadFailed(itemID, message):
                if itemID == currentLoadID { loaded = false; phase = "Could not play"; errorMessage = message; updateSystemPlayback() }
            case .restarted: playbackRevision += 1
            case let .screenshotWritten(path): notice = "Saved screenshot: \(URL(fileURLWithPath: path).lastPathComponent)"
            case let .ended(id, reason, error):
                guard id == activeEntry, activeLoadID == currentLoadID else { continue }
                if reason == 0 {
                    saveProgress(completed: true); loaded = false; phase = "Finished"
                    if preferences.autoNext { next(automatic: true) }
                } else if let error {
                    loaded = false; phase = "Could not play"; errorMessage = "Playback failed: \(error). Check that the file or drive is available and contains readable media."
                }
                updateSystemPlayback()
            case let .error(message): errorMessage = message; if loaded { engine?.refresh(itemID: currentLoadID) }
            }
        }
        if loaded { phase = (values["paused-for-cache"]?.flag ?? false) ? "Buffering…" : (paused ? "Paused" : "Playing") }
    }
    private func updateProperty(_ name: String, _ value: EngineValue) {
        values[name] = value
        if name == "time-pos", loaded, Date().timeIntervalSince(lastHistoryWrite) > 5 { saveProgress() }
        if name == "time-pos", loaded, paused || Date().timeIntervalSince(lastSystemPlaybackUpdate) >= 1 { updateSystemPlayback() }
        if name == "pause" || name == "duration" || name == "speed" { updateSystemPlayback() }
        if name == "volume" { preferences.volume = value.number }
    }
    private func finishLoading() {
        deferredLoadedEntry = nil
        loaded = true; phase = "Playing"
        resetAdjustments(); notice = nil
        if let record = pendingRestore {
            set("sub-delay", record.subtitleDelay); set("audio-delay", record.audioDelay)
            if preferences.resumePlayback, record.resumePosition > 0 {
                engine?.command(["seek", String(record.resumePosition), "absolute+exact"])
                notice = "Resumed at \(TimeText.string(record.resumePosition))"
            }
        }
        pendingRestore = nil
        if let itemID = currentItem?.id { pendingSubtitles.removeValue(forKey: itemID)?.forEach(attachSubtitle) }
        engine?.refresh(itemID: currentLoadID)
        updateSystemPlayback()
    }
    func saveProgress(completed: Bool = false) {
        guard preferences.rememberHistory, loaded, let item = currentItem, item.url.isFileURL else { return }
        let record = ResumeRecord(url: item.url, bookmark: item.bookmark, position: completed ? 0 : position, duration: duration, subtitleDelay: subtitleDelay, audioDelay: audioDelay)
        history = DiskStore.retaining(history, replacing: record)
        lastHistoryWrite = Date()
        do { try store.write(history, name: "history.json") }
        catch { Logger(subsystem: "com.aliahad.videoplayer", category: "history").error("Could not save playback history") }
    }
    private func configureRemoteControls() {
        let center = MPRemoteCommandCenter.shared()
        func register(_ command: MPRemoteCommand, _ action: @escaping @MainActor () -> Void) {
            let target = command.addTarget { _ in DispatchQueue.main.async(execute: action); return .success }
            remoteTargets.append((command, target))
        }
        register(center.togglePlayPauseCommand) { [weak self] in self?.togglePause() }
        register(center.playCommand) { [weak self] in self?.engine?.set("pause", false) }
        register(center.pauseCommand) { [weak self] in self?.engine?.set("pause", true) }
        register(center.nextTrackCommand) { [weak self] in self?.next() }
        register(center.previousTrackCommand) { [weak self] in self?.previous() }
    }
    private func updateSystemPlayback() {
        lastSystemPlaybackUpdate = Date()
        let info = MPNowPlayingInfoCenter.default()
        info.nowPlayingInfo = currentItem.map { [MPMediaItemPropertyTitle: $0.title, MPMediaItemPropertyPlaybackDuration: duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: position, MPNowPlayingInfoPropertyPlaybackRate: playing ? speed : 0] }
        info.playbackState = playing ? .playing : .paused
        if playing, powerAssertion == 0 {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Video playback" as CFString, &powerAssertion)
        } else if !playing, powerAssertion != 0 { IOPMAssertionRelease(powerAssertion); powerAssertion = 0 }
    }
    func shutdown(_ completion: @escaping @Sendable () -> Void) {
        openTask?.cancel(); saveProgress()
        try? store.write(preferences, name: "preferences.json")
        remoteTargets.forEach { $0.0.removeTarget($0.1) }; remoteTargets = []
        if powerAssertion != 0 { IOPMAssertionRelease(powerAssertion); powerAssertion = 0 }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        renderer?.stop(); renderer = nil
        scopes.forEach { $0.stopAccessingSecurityScopedResource() }; scopes = []
        if let engine { engine.shutdown(completion: completion) } else { completion() }
    }
}
