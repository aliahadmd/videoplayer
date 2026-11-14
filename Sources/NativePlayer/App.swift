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
import SwiftUI
import PlayerCore

@main struct LiPlayerApp {
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
    private var workspaceTest: WorkspaceSelfTest?
    private var sleepObserver: NSObjectProtocol?
    var testExitStatus: Int32 = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        let testIndex = arguments.firstIndex(of: "--self-test")
        let testDirectory = testIndex.flatMap { $0 + 1 < arguments.count ? URL(fileURLWithPath: arguments[$0 + 1]) : nil }
        let workspaceIndex = arguments.firstIndex(of: "--workspace-self-test")
        let workspaceDirectory = workspaceIndex.flatMap { $0 + 1 < arguments.count ? URL(fileURLWithPath: arguments[$0 + 1]) : nil }
        let isQA = Bundle.main.bundleIdentifier?.hasSuffix(".qa") == true
        let isolatedDirectory = workspaceDirectory?.appendingPathComponent("State") ?? testDirectory?.appendingPathComponent("Session-\(UUID().uuidString)") ?? (isQA ? FileManager.default.temporaryDirectory.appendingPathComponent("LiPlayer-QA-\(UUID().uuidString)") : nil)
        let session = PlayerSession(directory: isolatedDirectory)
        if isolatedDirectory != nil { session.preferences.volume = 0; session.preferences.rememberHistory = false; session.applyPreferences() }
        if workspaceDirectory != nil { session.preferences.rememberHistory = true; session.preferences.resumePlayback = true; session.preferences.rememberWorkspace = true }
        self.session = session
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.session?.saveProgress() }
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "LiPlayer"; window.minSize = NSSize(width: 720, height: 480)
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
        if let workspaceDirectory {
            let test = WorkspaceSelfTest(session: session, directory: workspaceDirectory)
            workspaceTest = test; test.start()
        }
        else if let testDirectory {
            let test = PlaybackSelfTest(session: session, directory: testDirectory)
            selfTest = test; test.start()
        }
        else if !pendingURLs.isEmpty { session.prepareForLaunch(restorePlayback: false); session.open(pendingURLs); pendingURLs = [] }
        else {
            let paths = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }.map { URL(fileURLWithPath: $0) }
            session.prepareForLaunch(restorePlayback: paths.isEmpty)
            if !paths.isEmpty { session.open(paths) }
        }
    }
    func application(_ sender: NSApplication, open urls: [URL]) { if let session { playerWindow?.makeKeyAndOrderFront(nil); session.open(urls) } else { pendingURLs += urls } }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { playerWindow?.makeKeyAndOrderFront(nil); return true }
    func applicationDidResignActive(_ notification: Notification) { session?.fullscreen.reveal(); session?.saveProgress() }
    func applicationDidBecomeActive(_ notification: Notification) { if session?.showLibrary == true { session?.library.refreshIfNeeded() } }
    func applicationWillTerminate(_ notification: Notification) { if selfTest != nil || workspaceTest != nil { exit(testExitStatus) } }
    func windowWillClose(_ notification: Notification) { if (notification.object as? NSWindow) === playerWindow { session?.fullscreen.exit(); session?.stop() } }
    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
        proposedOptions.subtracting(.hideMenuBar).union([.fullScreen, .autoHideMenuBar, .autoHideToolbar])
    }
    func windowWillEnterFullScreen(_ notification: Notification) { if let window = notification.object as? NSWindow, window === playerWindow { session?.fullscreen.enter(window) } }
    func windowDidEnterFullScreen(_ notification: Notification) { session?.fullscreen.entered() }
    func windowWillExitFullScreen(_ notification: Notification) { session?.fullscreen.willExit() }
    func windowDidExitFullScreen(_ notification: Notification) { session?.fullscreen.exit() }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) { session?.fullscreen.exit() }
    func windowDidFailToExitFullScreen(_ window: NSWindow) { session?.fullscreen.entered() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
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
        case .toggleLibrary: item.state = session.showLibrary ? .on : .off
        case .toggleQueue: item.state = session.showQueue ? .on : .off
        case .toggleInspector: item.state = session.showInspector ? .on : .off
        case .alwaysOnTop: item.state = session.floating ? .on : .off
        case .compactPlayer: item.state = session.compact ? .on : .off
        default: break
        }
        switch command {
        case .open, .openFolder, .openURL, .addFiles, .toggleLibrary, .toggleQueue, .toggleInspector, .commands, .fullscreen, .alwaysOnTop, .compactPlayer: return true
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
    @objc func about(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "LiPlayer",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development",
            .credits: NSAttributedString(string: "Copyright © 2026 Ali Ahad · LI Labs\nNative playback with libmpv, FFmpeg and libass.\nGNU General Public License v3.0 (GPLv3) · See Settings → About for source and notices.")
        ])
    }
    private func buildMenu() {
        let main = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(); let menu = NSMenu(title: title); item.submenu = menu; main.addItem(item); return menu
        }
        let app = submenu("LiPlayer")
        app.addItem(withTitle: "About LiPlayer", action: #selector(about(_:)), keyEquivalent: "").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Hide LiPlayer", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hide = app.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h"); hide.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator()); app.addItem(withTitle: "Quit LiPlayer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        add([.toggleLibrary, .toggleQueue, .toggleInspector, .compactPlayer, .commands], to: submenu("View"))
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
        if event.window === playerWindow { session?.fullscreen.reveal() }
        guard let session, event.window === playerWindow, !(event.window?.firstResponder is NSTextView), !session.showCommands, !session.showJump else { return event }
        let named: [UInt16: String] = [49: "space", 123: "left", 124: "right", 125: "down", 126: "up", 51: "backspace", 36: "return", 53: "escape"]
        guard let key = named[event.keyCode] ?? event.charactersIgnoringModifiers?.lowercased() else { return event }
        if key == "escape", session.fullscreen.active { session.perform(.fullscreen); return nil }
        var modifiers: Set<String> = []
        if event.modifierFlags.contains(.command) { modifiers.insert("cmd") }; if event.modifierFlags.contains(.control) { modifiers.insert("ctrl") }; if event.modifierFlags.contains(.option) { modifiers.insert("alt") }; if event.modifierFlags.contains(.shift) { modifiers.insert("shift") }
        if modifiers.isEmpty, ["left", "right", "up", "down"].contains(key) {
            var view = event.window?.firstResponder as? NSView
            while let focused = view {
                if focused is NSTableView { return event }
                view = focused.superview
            }
        }
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
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.init("toggleLibrary"), .init("open"), .init("openFolder"), .flexibleSpace, .init("toggleQueue"), .init("toggleInspector")] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let command = PlayerCommand(rawValue: identifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = command.title; item.toolTip = command.title
        let symbols: [PlayerCommand: String] = [.open: "doc", .openFolder: "folder.badge.plus", .toggleLibrary: "sidebar.left", .toggleQueue: "list.bullet", .toggleInspector: "sidebar.right"]
        item.image = NSImage(systemSymbolName: symbols[command] ?? "sidebar.right", accessibilityDescription: command.title)
        item.target = target; item.action = #selector(AppDelegate.toolbarAction(_:)); return item
    }
}
