// SPDX-License-Identifier: GPL-3.0-or-later
//
// LiPlayer — Native macOS video player built with Swift, AppKit, SwiftUI, and libmpv.
// Copyright (C) 2026 Ali Ahad <https://aliahad.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

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
    var queue = PlaybackQueue() { didSet { saveWorkspace() } }
    let library: FolderLibrary
    let fullscreen = FullscreenControls()
    private var windowLibrary = false { didSet { saveWorkspace() } }
    private var fullscreenLibrary = false
    private var fullscreenSidebar: Sidebar?
    var showLibrary: Bool {
        get { fullscreen.active ? fullscreenLibrary : windowLibrary }
        set { if fullscreen.active { fullscreenLibrary = newValue; fullscreen.reveal() } else { windowLibrary = newValue } }
    }
    private(set) var workspaceSaveError: String?
    private(set) var workspaceSaving = false
    var currentItem: MediaItem?
    var values: [String: EngineValue] = [:]
    var loaded = false
    var phase = "Ready"
    var errorMessage: String?
    var notice: String?
    private enum Sidebar: String { case queue, inspector }
    private var sidebar: Sidebar? { didSet { saveWorkspace() } }
    var showQueue: Bool {
        get { (fullscreen.active ? fullscreenSidebar : sidebar) == .queue }
        set {
            if fullscreen.active { if newValue { fullscreenSidebar = .queue } else if fullscreenSidebar == .queue { fullscreenSidebar = nil }; fullscreen.reveal() }
            else { if newValue { sidebar = .queue } else if sidebar == .queue { sidebar = nil } }
        }
    }
    var showInspector: Bool {
        get { (fullscreen.active ? fullscreenSidebar : sidebar) == .inspector }
        set {
            if fullscreen.active { if newValue { fullscreenSidebar = .inspector } else if fullscreenSidebar == .inspector { fullscreenSidebar = nil }; fullscreen.reveal() }
            else { if newValue { sidebar = .inspector } else if sidebar == .inspector { sidebar = nil } }
        }
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
    weak var videoView: NSView?
    weak var window: NSWindow?
    var settingsAction: (() -> Void)?
    var bindingsChanged: (() -> Void)?
    private let store: DiskStore
    private let workspaceWriter: WorkspaceWriter
    private var workspaceRevision = 0
    private var workspaceReady = false
    private var closing = false
    private var savedWorkspace: WorkspaceState
    private var workspacePlayback: ResumeRecord?
    private var restoreTask: Task<Void, Never>?
    private var restoredSpeed: Double?
    private var workspaceSpeed = 1.0
    private var pendingWorkspacePosition: Double?
    private var startupResumeTarget: Double?
    private var pendingLibraryNotice: String?
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

    init(directory explicitDirectory: URL? = nil) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = explicitDirectory ?? appSupport.appendingPathComponent("LiPlayer")
        if explicitDirectory == nil {
            DiskStore.migrateIfNeeded(from: appSupport.appendingPathComponent("VideoPlayer"), to: directory)
        }
        store = DiskStore(directory: directory)
        workspaceWriter = WorkspaceWriter(directory: directory)
        let settings = store.read(Preferences.self, name: "preferences.json") ?? Preferences()
        preferences = settings
        history = store.read([ResumeRecord].self, name: "history.json") ?? []
        if !settings.rememberHistory { history = [] }
        var restored = WorkspaceState()
        var restorationError: String?
        if settings.rememberWorkspace {
            do {
                let result = try WorkspaceStore(directory: directory).load()
                restored = result.state
                if result.recovered { notice = "Recovered your library and queue from the last saved backup." }
            } catch { restorationError = error.localizedDescription }
        }
        savedWorkspace = restored
        workspaceSpeed = restored.speed
        workspacePlayback = settings.rememberHistory ? restored.playback : nil
        library = FolderLibrary(folders: restored.folders)
        queue.replace(restored.queue)
        if let id = restored.currentID { queue.select(id) }
        queue.repeatMode = restored.repeatMode
        showLibrary = restored.showLibrary
        sidebar = restored.sidebar.flatMap(Sidebar.init(rawValue:))
        do {
            engine = try PlaybackEngine { [weak self] events in
                DispatchQueue.main.async { self?.receive(events) }
            }
            applyPreferences()
        } catch { errorMessage = error.localizedDescription }
        configureRemoteControls()
        library.changed = { [weak self] in self?.saveWorkspace() }
        library.reportError = { [weak self] in self?.errorMessage = $0 }
        library.relocated = { [weak self] previous, next in self?.relocateWorkspace(from: previous, to: next) }
        workspaceSaveError = restorationError
        workspaceReady = true
        fullscreen.canHide = { [weak self] in
            guard let self else { return false }
            return self.playing && self.tracks.contains { $0.type == "video" } && self.values["paused-for-cache"]?.flag != true && self.errorMessage == nil && self.workspaceSaveError == nil && !self.showCommands && !self.showJump && !self.fullscreenLibrary && self.fullscreenSidebar == nil
        }
        fullscreen.onExit = { [weak self] in self?.fullscreenLibrary = false; self?.fullscreenSidebar = nil }
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
        saveWorkspace(sanitizeBackup: !preferences.rememberWorkspace || !preferences.rememberHistory)
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
        workspacePlayback = nil
        do { try store.write(history, name: "history.json") }
        catch { errorMessage = "Could not clear history: \(error.localizedDescription)" }
        NSDocumentController.shared.clearRecentDocuments(nil)
        saveWorkspace(sanitizeBackup: true)
    }
    func openPanel(folder: Bool = false, append: Bool = false, subtitle: Bool = false) {
        window?.makeKeyAndOrderFront(nil)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = folder
        panel.canChooseFiles = !folder
        panel.allowsMultipleSelection = !subtitle
        panel.message = subtitle ? "Choose a subtitle file to attach to the current video." : folder ? "Add folders to your saved library. Expand subfolders to browse their videos." : "Choose media files."
        panel.prompt = append ? "Add" : "Open"
        guard panel.runModal() == .OK else { return }
        if subtitle { panel.urls.forEach(attachSubtitle) } else if folder { addLibraryFolders(panel.urls) } else { open(panel.urls, append: append) }
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
        restoreTask?.cancel()
        if urls.allSatisfy(MediaFiles.isSubtitle) { urls.forEach(attachSubtitle); return }
        openTask?.cancel()
        let request = UUID(); openingID = request
        for url in urls where url.isFileURL { retainAccess(to: url) }
        openTask = Task { [weak self] in
            do {
                let folders = try await Self.selectedFolders(in: urls)
                let files = urls.filter { !folders.contains($0) }
                let expanded = try await MediaFiles.expand(files)
                guard !Task.isCancelled, let self, self.openingID == request else { return }
                if !folders.isEmpty { self.addLibraryFolders(folders) }
                if files.isEmpty { return }
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
    private func load(_ item: MediaItem, paused: Bool = false, restore: ResumeRecord? = nil, startupRestore: Bool = false) {
        currentLoadID = UUID()
        currentItem = item; loaded = false; phase = "Opening…"; errorMessage = nil; notice = nil
        if !startupRestore { workspaceSpeed = 1 }
        values = values.filter { globalProperties.contains($0.key) }
        pendingRestore = preferences.rememberHistory ? (restore ?? history.first { $0.url == item.url }) : nil
        pendingWorkspacePosition = restore.flatMap { $0.position.isFinite && $0.position >= 0 && $0.duration.isFinite && $0.duration > 0 && $0.position < $0.duration - 0.25 ? $0.position : nil }
        startupResumeTarget = startupRestore ? pendingWorkspacePosition ?? 0 : nil
        if item.url.isFileURL {
            if let folder = library.folders.first(where: { item.url.path.hasPrefix($0.url.path + "/") }) { retainAccess(to: folder.url) }
            else { retainAccess(to: item.url) }
        }
        engine?.command(["loadfile", item.url.isFileURL ? item.url.path : item.url.absoluteString, "replace"], itemID: currentLoadID)
        engine?.set("pause", paused)
        window?.title = item.title
        saveWorkspace()
    }
    func attachSubtitle(_ url: URL) {
        guard loaded else { errorMessage = "Open a video before adding subtitles."; return }
        guard MediaFiles.isSubtitle(url) else { errorMessage = "Choose an SRT, ASS, VTT, or another supported subtitle file."; return }
        retainAccess(to: url)
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
    func stop() { saveProgress(); engine?.command(["stop"]); loaded = false; phase = "Stopped"; updateSystemPlayback(); saveWorkspace() }
    func seek(_ seconds: Double) {
        guard loaded, seekable, seconds.isFinite else { return }
        engine?.command(["seek", String(max(0, min(seconds, duration > 0 ? duration : seconds))), "absolute+exact"])
    }
    func set(_ name: String, _ value: Double) {
        guard value.isFinite else { return }
        let value = PlaybackEngine.normalized(name, value)
        values[name] = .number(value)
        if name == "speed" { workspaceSpeed = min(4, max(0.25, value)) }
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
        case .toggleLibrary: showLibrary.toggle()
        case .toggleQueue: showQueue.toggle(); if showQueue { showInspector = false }
        case .toggleInspector: showInspector.toggle(); if showInspector { showQueue = false }
        case .commands: showCommands = true; case .jumpToTime: showJump = true
        case .fullscreen: if !fullscreen.transitioning { window?.toggleFullScreen(nil) }
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
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Watch queue.lpqueue"
        panel.allowedContentTypes = [UTType(exportedAs: "com.aliahad.liplayer.queue", conformingTo: .json)]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Playlist.encode(queue.items.map(\.url)).write(to: url, options: .atomic); notice = "Queue saved" }
        catch { errorMessage = error.localizedDescription }
    }
    private func toggleCompact() {
        guard let window, !fullscreen.active, !fullscreen.transitioning, !window.styleMask.contains(.fullScreen) else { return }
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
            case .restarted: playbackRevision += 1; if loaded { saveProgress() }
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
        if name == "time-pos", loaded, let target = startupResumeTarget, abs(value.number - target) < 0.12 {
            startupResumeTarget = nil
            saveProgress()
        }
        if name == "speed", value.number.isFinite, (0.25...4).contains(value.number) { workspaceSpeed = value.number }
        if name == "time-pos", loaded, Date().timeIntervalSince(lastHistoryWrite) > 5 { saveProgress() }
        if name == "time-pos", loaded, paused || Date().timeIntervalSince(lastSystemPlaybackUpdate) >= 1 { updateSystemPlayback() }
        if name == "pause" || name == "duration" || name == "speed" { updateSystemPlayback() }
        if name == "pause", value.flag, loaded { saveProgress() }
        if ["pause", "paused-for-cache", "track-list"].contains(name) { fullscreen.evaluate() }
        if name == "volume" { preferences.volume = value.number }
    }
    private func finishLoading() {
        deferredLoadedEntry = nil
        loaded = true; phase = "Playing"
        resetAdjustments(); notice = nil
        if let record = pendingRestore {
            set("sub-delay", record.subtitleDelay); set("audio-delay", record.audioDelay)
            let resumePosition = pendingWorkspacePosition ?? record.resumePosition
            if preferences.resumePlayback, resumePosition > 0 {
                engine?.command(["seek", String(resumePosition), "absolute+exact"])
                notice = "Resumed at \(TimeText.string(resumePosition))"
            }
        }
        pendingRestore = nil
        pendingWorkspacePosition = nil
        if let restoredSpeed { set("speed", restoredSpeed); self.restoredSpeed = nil }
        if let pendingLibraryNotice { notice = pendingLibraryNotice; self.pendingLibraryNotice = nil }
        if let itemID = currentItem?.id { pendingSubtitles.removeValue(forKey: itemID)?.forEach(attachSubtitle) }
        engine?.refresh(itemID: currentLoadID)
        updateSystemPlayback()
        saveWorkspace()
    }
    func saveProgress(completed: Bool = false) {
        lastHistoryWrite = Date()
        defer { saveWorkspace() }
        guard preferences.rememberHistory, loaded, startupResumeTarget == nil, let item = currentItem, item.url.isFileURL else { return }
        let record = ResumeRecord(url: item.url, bookmark: item.bookmark, position: completed ? 0 : position, duration: duration, subtitleDelay: subtitleDelay, audioDelay: audioDelay)
        history = DiskStore.retaining(history, replacing: record)
        workspacePlayback = record
        lastHistoryWrite = Date()
        do { try store.write(history, name: "history.json") }
        catch { Logger(subsystem: "com.aliahad.liplayer", category: "history").error("Could not save playback history") }
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
        openTask?.cancel(); restoreTask?.cancel(); library.stop(); fullscreen.exit(); saveProgress()
        let finalState = workspaceState()
        workspaceRevision += 1
        let revision = workspaceRevision
        closing = true
        try? store.write(preferences, name: "preferences.json")
        remoteTargets.forEach { $0.0.removeTarget($0.1) }; remoteTargets = []
        if powerAssertion != 0 { IOPMAssertionRelease(powerAssertion); powerAssertion = 0 }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        renderer?.stop(); renderer = nil
        scopes.forEach { $0.stopAccessingSecurityScopedResource() }; scopes = []
        let sanitizeBackup = !preferences.rememberWorkspace || !preferences.rememberHistory
        Task.detached(priority: .utility) { [workspaceWriter, engine] in
            do { try await workspaceWriter.save(finalState, revision: revision, sanitizeBackup: sanitizeBackup) }
            catch { Logger(subsystem: "com.aliahad.liplayer", category: "workspace").error("Could not save the final workspace: \(error.localizedDescription)") }
            if let engine { engine.shutdown(completion: completion) } else { completion() }
        }
    }

    @concurrent private static func selectedFolders(in urls: [URL]) async throws -> [URL] {
        try urls.filter { url in
            try Task.checkCancellation()
            return url.isFileURL && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }
    func addLibraryFolders(_ urls: [URL]) { library.add(urls); showLibrary = true }
    func playLibraryNode(_ node: LibraryNode) {
        guard !node.isFolder else { return }
        restoreTask?.cancel(); openTask?.cancel(); openingID = UUID()
        saveProgress()
        if let folder = library.folders.first(where: { $0.id == node.location.rootID }) { retainAccess(to: folder.url) }
        let siblings = library.mediaSiblings(of: node)
        let window = LibraryFiles.queueWindow(siblings, selecting: node.id)
        pendingLibraryNotice = window.count < siblings.count ? "This queue contains 10,000 nearby videos. Every video is still available in Library." : nil
        // One root bookmark grants access to its children; avoid filesystem work per file.
        let items = window.map { MediaItem(url: $0.url) }
        queue.replace(items)
        if let item = items.first(where: { $0.url == node.url }) { queue.select(item.id); load(item) }
    }
    private func retainAccess(to url: URL) {
        if !scopes.contains(url), url.startAccessingSecurityScopedResource() { scopes.append(url) }
    }
    func prepareForLaunch(restorePlayback: Bool) {
        library.refreshAll()
        guard restorePlayback, preferences.rememberWorkspace, let item = queue.current else { return }
        currentItem = item; phase = "Ready to resume"
        restoreTask = Task { [weak self] in
            guard let self else { return }
            await self.library.waitForRoot(containing: item.url)
            guard !Task.isCancelled, let current = self.queue.current, current.id == item.id else { return }
            let result = await Self.resolveSavedItem(current)
            let resolved = result.item
            guard !Task.isCancelled, self.queue.current?.id == item.id else { return }
            if let previous = self.queue.current?.url, previous != resolved.url, self.workspacePlayback?.url == previous {
                self.workspacePlayback?.url = resolved.url
                self.workspacePlayback?.bookmark = resolved.bookmark
            }
            self.currentItem = resolved
            self.queue.update(resolved)
            guard resolved.url.isFileURL else { self.phase = "Ready to resume"; return }
            guard result.readable else { self.phase = "File unavailable"; self.notice = "Reconnect the drive or select a video in your library. Your queue has been kept."; return }
            self.restoredSpeed = self.savedWorkspace.speed
            let checkpoint = self.workspacePlayback.flatMap { $0.url == resolved.url ? $0 : nil }
            self.load(resolved, paused: true, restore: self.preferences.resumePlayback ? checkpoint : nil, startupRestore: true)
        }
    }
    @concurrent private static func resolveSavedItem(_ item: MediaItem) async -> (item: MediaItem, readable: Bool) {
        var resolved = item
        if let bookmark = item.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting], bookmarkDataIsStale: &stale) {
                resolved = MediaItem(url: url, id: item.id, bookmark: stale ? try? url.bookmarkData(options: .withSecurityScope) : bookmark)
            }
        }
        let scoped = resolved.url.startAccessingSecurityScopedResource()
        defer { if scoped { resolved.url.stopAccessingSecurityScopedResource() } }
        return (resolved, !resolved.url.isFileURL || FileManager.default.isReadableFile(atPath: resolved.url.path))
    }
    private func workspaceState() -> WorkspaceState {
        guard preferences.rememberWorkspace else { return WorkspaceState() }
        var state = WorkspaceState()
        state.folders = library.folders; state.queue = queue.items; state.currentID = queue.currentID
        state.repeatMode = queue.repeatMode; state.showLibrary = windowLibrary; state.sidebar = sidebar?.rawValue
        state.speed = workspaceSpeed
        if preferences.rememberHistory, let item = currentItem, item.id == queue.currentID, item.url == queue.current?.url, item.url.isFileURL {
            if loaded && startupResumeTarget == nil { state.playback = ResumeRecord(url: item.url, bookmark: item.bookmark, position: position, duration: duration, subtitleDelay: subtitleDelay, audioDelay: audioDelay) }
            else if workspacePlayback?.url == item.url { state.playback = workspacePlayback }
        }
        return state
    }
    func saveWorkspace(sanitizeBackup: Bool = false) {
        guard workspaceReady, !closing else { return }
        let state = workspaceState()
        workspaceRevision += 1
        let revision = workspaceRevision
        workspaceSaving = true
        Task { [weak self, workspaceWriter] in
            do {
                try await workspaceWriter.save(state, revision: revision, sanitizeBackup: sanitizeBackup)
                guard let self, self.workspaceRevision == revision else { return }
                self.workspaceSaving = false; self.workspaceSaveError = nil
            } catch {
                guard let self, self.workspaceRevision == revision else { return }
                self.workspaceSaving = false; self.workspaceSaveError = "Could not save the library: \(error.localizedDescription)"
            }
        }
    }
    private func relocateWorkspace(from previous: URL, to next: URL) {
        func moved(_ url: URL) -> URL {
            guard url.isFileURL, url.path.hasPrefix(previous.path + "/") else { return url }
            return next.appendingPathComponent(String(url.path.dropFirst(previous.path.count + 1)))
        }
        func record(_ original: ResumeRecord) -> ResumeRecord {
            var result = original
            result.url = moved(original.url)
            if result.url != original.url { result.bookmark = nil }
            return result
        }
        workspacePlayback = workspacePlayback.map(record)
        pendingRestore = pendingRestore.map(record)
        let selected = queue.currentID
        let items = queue.items.map { item in
            let url = moved(item.url)
            return url == item.url ? item : MediaItem(url: url, id: item.id)
        }
        queue.replace(items)
        if let selected { queue.select(selected) }
        if let item = currentItem { currentItem = items.first { $0.id == item.id } ?? item }
        history = history.map(record)
        do { try store.write(history, name: "history.json") }
        catch { errorMessage = "Could not update history for the relocated folder." }
        saveWorkspace()
    }
}
