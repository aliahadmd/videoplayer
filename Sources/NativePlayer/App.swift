import AppKit
import SwiftUI
import PlayerCore

@main struct VideoPlayerApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation, NSMenuDelegate {
    var session: PlayerSession?
    private var playerWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var keyMonitor: Any?
    private var pendingURLs: [URL] = []
    private var terminating = false
    private var selfTest: PlaybackSelfTest?
    var testExitStatus: Int32 = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        let testIndex = arguments.firstIndex(of: "--self-test")
        let testDirectory = testIndex.flatMap { $0 + 1 < arguments.count ? URL(fileURLWithPath: arguments[$0 + 1]) : nil }
        let isQA = Bundle.main.bundleIdentifier?.hasSuffix(".qa") == true
        let isolatedDirectory = testDirectory?.appendingPathComponent("Session-\(UUID().uuidString)") ?? (isQA ? FileManager.default.temporaryDirectory.appendingPathComponent("VideoPlayer-QA-\(UUID().uuidString)") : nil)
        let session = PlayerSession(directory: isolatedDirectory)
        if isolatedDirectory != nil { session.preferences.volume = 0; session.preferences.rememberHistory = false; session.applyPreferences() }
        self.session = session
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Video Player"; window.minSize = NSSize(width: 720, height: 480)
        window.isReleasedWhenClosed = false; window.delegate = self
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentView = NSHostingView(rootView: PlayerRootView(session: session))
        window.center(); window.setFrameAutosaveName("PlayerWindow")
        session.window = window
        session.settingsAction = { [weak self] in self?.showSettings(nil) }
        session.bindingsChanged = { [weak self] in self?.buildMenu() }
        playerWindow = window
        buildMenu(); buildToolbar(window)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if let testDirectory {
            let test = PlaybackSelfTest(session: session, directory: testDirectory)
            selfTest = test; test.start()
        }
        else if !pendingURLs.isEmpty { session.open(pendingURLs); pendingURLs = [] }
        else {
            let paths = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }.map { URL(fileURLWithPath: $0) }
            if !paths.isEmpty { session.open(paths) }
        }
    }
    func application(_ sender: NSApplication, open urls: [URL]) { if let session { playerWindow?.makeKeyAndOrderFront(nil); session.open(urls) } else { pendingURLs += urls } }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { playerWindow?.makeKeyAndOrderFront(nil); return true }
    func applicationWillTerminate(_ notification: Notification) { if selfTest != nil { exit(testExitStatus) } }
    func windowWillClose(_ notification: Notification) { if (notification.object as? NSWindow) === playerWindow { session?.stop() } }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        guard let session else { return .terminateNow }
        session.shutdown {
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                MainActor.assumeIsolated { NSApp.reply(toApplicationShouldTerminate: true) }
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
        return .terminateLater
    }
    @objc func commandAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let command = PlayerCommand(rawValue: raw) else { return }
        session?.perform(command)
    }
    @objc func recentAction(_ sender: NSMenuItem) {
        guard let record = sender.representedObject as? ResumeRecord else { return }
        session?.openRecent(record)
    }
    @objc func clearRecentAction(_ sender: Any?) { session?.clearHistory() }
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.identifier?.rawValue == "PlaybackHistory" else { return }
        menu.removeAllItems()
        let records = Array((session?.history ?? []).prefix(30))
        for record in records {
            let item = NSMenuItem(title: record.url.lastPathComponent, action: #selector(recentAction(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = record
            item.toolTip = record.url.deletingLastPathComponent().path
            menu.addItem(item)
        }
        if records.isEmpty { let item = NSMenuItem(title: "No Recent Files", action: nil, keyEquivalent: ""); item.isEnabled = false; menu.addItem(item) }
        else { menu.addItem(.separator()); menu.addItem(withTitle: "Clear History", action: #selector(clearRecentAction(_:)), keyEquivalent: "").target = self }
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let session, let raw = item.representedObject as? String, let command = PlayerCommand(rawValue: raw) else { return true }
        switch command {
        case .toggleQueue: item.state = session.showQueue ? .on : .off
        case .toggleInspector: item.state = session.showInspector ? .on : .off
        case .alwaysOnTop: item.state = session.floating ? .on : .off
        case .compactPlayer: item.state = session.compact ? .on : .off
        default: break
        }
        switch command {
        case .open, .openFolder, .openURL, .addFiles, .toggleQueue, .toggleInspector, .commands, .fullscreen, .alwaysOnTop, .compactPlayer: return true
        case .saveQueue: return !session.queue.items.isEmpty
        case .togglePause: return session.currentItem != nil
        case .next: return session.queue.followingIndex(automatic: false) != nil
        case .previous: return (session.queue.currentIndex ?? 0) > 0
        case .backward, .forward, .longBackward, .longForward, .jumpToTime, .loopA, .loopB: return session.loaded && session.seekable
        default: return session.loaded
        }
    }
    @objc func toolbarAction(_ sender: NSToolbarItem) {
        guard let command = PlayerCommand(rawValue: sender.itemIdentifier.rawValue) else { return }
        session?.perform(command)
    }
    @objc func showSettings(_ sender: Any?) {
        guard let session else { return }
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(session: session))
            let window = NSWindow(contentViewController: controller)
            window.title = "Settings"; window.styleMask = [.titled, .closable]; window.isReleasedWhenClosed = false; window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc func about(_ sender: Any?) { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Video Player", .applicationVersion: "0.1.0", .credits: NSAttributedString(string: "Native playback with libmpv, FFmpeg and libass.\nGPLv3 · See Settings → About for dependency notices.")]) }
    private func buildMenu() {
        let main = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(); let menu = NSMenu(title: title); item.submenu = menu; main.addItem(item); return menu
        }
        let app = submenu("Video Player")
        app.addItem(withTitle: "About Video Player", action: #selector(about(_:)), keyEquivalent: "").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Video Player", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hide = app.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h"); hide.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator()); app.addItem(withTitle: "Quit Video Player", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let files = submenu("File")
        add([.open, .openFolder, .openURL, .addFiles, .saveQueue, .attachSubtitle], to: files)
        files.addItem(.separator())
        let recent = NSMenu(title: "Open Recent"); recent.identifier = .init("PlaybackHistory"); recent.delegate = self
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: ""); recentItem.submenu = recent; files.addItem(recentItem)
        let edit = submenu("Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z"); redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        add([.togglePause, .stop, .backward, .forward, .longBackward, .longForward, .previous, .next, .frameBackward, .frameForward, .jumpToTime, .speedDown, .speedUp, .normalSpeed, .loopA, .loopB, .clearLoop], to: submenu("Playback"))
        add([.fullscreen, .alwaysOnTop, .screenshot, .resetAdjustments], to: submenu("Video"))
        add([.volumeDown, .volumeUp, .mute, .audioEarlier, .audioLater], to: submenu("Audio"))
        add([.attachSubtitle, .subtitleEarlier, .subtitleLater], to: submenu("Subtitles"))
        add([.toggleQueue, .toggleInspector, .compactPlayer, .commands], to: submenu("View"))
        let windows = submenu("Window")
        windows.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windows.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.windowsMenu = windows
        add([.commands], to: submenu("Help"))
        NSApp.mainMenu = main
    }
    private func add(_ commands: [PlayerCommand], to menu: NSMenu) {
        for command in commands {
            let shortcut = Shortcut(session?.preferences.shortcuts[command.rawValue] ?? command.defaultShortcut)
            let hasCommand = shortcut?.modifiers.contains("cmd") == true
            let named = ["left": "\u{f702}", "right": "\u{f703}", "up": "\u{f700}", "down": "\u{f701}", "space": " ", "return": "\r", "backspace": "\u{8}", "escape": "\u{1b}"]
            let key = shortcut.map { named[$0.key] ?? $0.key } ?? ""
            let item = NSMenuItem(title: command.title, action: #selector(commandAction(_:)), keyEquivalent: hasCommand ? key : "")
            if hasCommand, let shortcut { item.keyEquivalentModifierMask = flags(shortcut.modifiers) }
            item.target = self; item.representedObject = command.rawValue
            item.toolTip = shortcut?.display
            menu.addItem(item)
        }
    }
    private func flags(_ modifiers: Set<String>) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains("cmd") { flags.insert(.command) }; if modifiers.contains("ctrl") { flags.insert(.control) }; if modifiers.contains("alt") { flags.insert(.option) }; if modifiers.contains("shift") { flags.insert(.shift) }
        return flags
    }
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard let session, event.window === playerWindow, !(event.window?.firstResponder is NSTextView), !session.showCommands, !session.showJump else { return event }
        let named: [UInt16: String] = [49: "space", 123: "left", 124: "right", 125: "down", 126: "up", 51: "backspace", 36: "return", 53: "escape"]
        guard let key = named[event.keyCode] ?? event.charactersIgnoringModifiers?.lowercased() else { return event }
        var modifiers: Set<String> = []
        if event.modifierFlags.contains(.command) { modifiers.insert("cmd") }; if event.modifierFlags.contains(.control) { modifiers.insert("ctrl") }; if event.modifierFlags.contains(.option) { modifiers.insert("alt") }; if event.modifierFlags.contains(.shift) { modifiers.insert("shift") }
        for command in PlayerCommand.allCases {
            if let shortcut = Shortcut(session.preferences.shortcuts[command.rawValue] ?? command.defaultShortcut), shortcut.key == key, shortcut.modifiers == modifiers {
                let repeatable: Set<PlayerCommand> = [.backward, .forward, .longBackward, .longForward, .frameForward, .frameBackward, .volumeUp, .volumeDown, .speedUp, .speedDown, .subtitleEarlier, .subtitleLater, .audioEarlier, .audioLater]
                if event.isARepeat && !repeatable.contains(command) { return nil }
                session.perform(command); return nil
            }
        }
        return event
    }
    private var toolbarDelegate: PlayerToolbar?
    private func buildToolbar(_ window: NSWindow) {
        let delegate = PlayerToolbar(target: self)
        toolbarDelegate = delegate
        let toolbar = NSToolbar(identifier: "PlayerToolbar"); toolbar.delegate = delegate
        toolbar.displayMode = .iconOnly; window.toolbar = toolbar; window.toolbarStyle = .unifiedCompact
    }
}

final class PlayerToolbar: NSObject, NSToolbarDelegate {
    weak var target: AppDelegate?
    init(target: AppDelegate) { self.target = target }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.init("open"), .flexibleSpace, .init("toggleQueue"), .init("toggleInspector")] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let command = PlayerCommand(rawValue: identifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = command.title; item.toolTip = command.title
        item.image = NSImage(systemSymbolName: command == .open ? "folder" : command == .toggleQueue ? "list.bullet" : "sidebar.right", accessibilityDescription: command.title)
        item.target = target; item.action = #selector(AppDelegate.toolbarAction(_:)); return item
    }
}
