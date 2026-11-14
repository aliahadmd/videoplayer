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
import PlayerCore

final class WorkspaceSelfTest {
    private let session: PlayerSession
    private let directory: URL
    private var checks: [String] = []
    private let phase: String
    init(session: PlayerSession, directory: URL) {
        self.session = session; self.directory = directory
        let arguments = CommandLine.arguments
        phase = arguments.firstIndex(of: "--workspace-phase").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil } ?? "save"
    }
    func start() {
        Task {
            do {
                try await run()
                write(success: true, error: nil)
                if phase == "crash" || CommandLine.arguments.contains("--stay-open") { return }
            } catch { write(success: false, error: error.localizedDescription) }
            NSApp.terminate(nil)
        }
    }
    private func wait(_ title: String, _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        guard predicate() else { throw EngineError.message("\(title) timed out: \(session.errorMessage ?? session.phase)") }
        checks.append(title)
    }
    private func check(_ title: String, _ value: Bool) throws {
        guard value else { throw EngineError.message("Failed: \(title)") }; checks.append(title)
    }
    private func persisted() -> WorkspaceState? { try? WorkspaceStore(directory: directory.appendingPathComponent("State")).load().state }
    private func run() async throws {
        try await wait("Native surface is ready") { session.renderer != nil }
        if phase == "save" {
            session.addLibraryFolders([directory.appendingPathComponent("Tree")])
            let root = session.library.folders[0].node
            try await wait("Root displays immediate folders and media") { session.library.children[root.id]?.count == 4 }
            try check("Root has natural folder and file order", session.library.children[root.id]?.map(\.title) == ["Season 2", "Season 10", "Episode 2.mp4", "Episode 10.mp4"])
            let season = session.library.children[root.id]![0]
            session.library.setExpanded(season, true)
            try await wait("Nested season expands") { session.library.children[season.id]?.count == 3 }
            let extras = session.library.children[season.id]![0]
            session.library.setExpanded(extras, true)
            try await wait("Third-level folder expands") { session.library.children[extras.id]?.count == 1 }
            let episode = session.library.children[season.id]![2]
            session.playLibraryNode(episode)
            try await wait("Selected nested video plays") { session.loaded && session.currentItem?.url == episode.url && session.position > 0.2 }
            try check("Queue contains the selected folder's videos", session.queue.items.count == 2 && session.queue.currentIndex == 1)
            session.set("pause", true)
            try await wait("Pause before saving") { session.paused }
            session.seek(2.25); session.set("sub-delay", 0.35); session.set("speed", 1.25)
            try await wait("Autosave records early playback position and timing") { guard let state = persisted() else { return false }; return abs((state.playback?.position ?? -1) - 2.25) < 0.12 && abs((state.playback?.subtitleDelay ?? -1) - 0.35) < 0.01 && state.speed == 1.25 }
            session.showLibrary = false
            try await wait("Hiding the library retains folders") { persisted()?.showLibrary == false && persisted()?.folders.count == 1 }
            session.showLibrary = true
            try await wait("Library and expansion state save without quitting") { persisted()?.showLibrary == true && persisted()?.folders.first?.expandedPaths == ["", "Season 2", "Season 2/Extras"] }
        } else {
            session.prepareForLaunch(restorePlayback: true)
            let expected = phase == "crash" ? 2.25 : 8.0
            try await wait("Fresh process restores the last video paused at \(expected)") { session.loaded && session.paused && abs(session.position - expected) < 0.12 }
            try check("Restored playback permits display sleep", !session.preventsDisplaySleep)
            try check("Fresh process restores queue selection", session.queue.items.count == 2 && session.queue.currentIndex == 1)
            try check("Library remains visible", session.showLibrary && session.library.folders.count == 1)
            let root = session.library.folders[0]
            let extras = LibraryLocation(rootID: root.id, path: "Season 2/Extras")
            try await wait("Expanded nested branches restore") { session.library.children[extras]?.count == 1 }
            let delay = phase == "crash" ? 0.35 : 0.6
            let speed = phase == "crash" ? 1.25 : 1.75
            try await wait("Timing and speed restore") { abs(session.subtitleDelay - delay) < 0.01 && abs(session.speed - speed) < 0.01 }
            if phase == "crash" {
                session.seek(8); session.set("sub-delay", 0.6); session.set("speed", 1.75)
                try await wait("Checkpoint reaches disk before forced termination") { guard let state = persisted() else { return false }; return abs((state.playback?.position ?? -1) - 8) < 0.12 && abs((state.playback?.subtitleDelay ?? -1) - 0.6) < 0.01 && state.speed == 1.75 }
            } else {
                let missing = directory.appendingPathComponent("Disconnected drive")
                session.addLibraryFolders([missing])
                let missingRoot = session.library.folders.last!
                try await wait("Unavailable folder stays in the library with a recoverable error") { session.library.failures[missingRoot.node.id] != nil && session.library.folders.count == 2 }
                let replacement = directory.appendingPathComponent("Replacement")
                try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
                session.library.relink(missingRoot.id, to: replacement)
                try await wait("Locating a folder preserves its identity and recovers browsing") { session.library.folders.last?.id == missingRoot.id && session.library.children[missingRoot.node.id] != nil && session.library.failures[missingRoot.node.id] == nil }
                session.library.remove(missingRoot.id)
                try check("Removing a library root leaves its directory on disk", FileManager.default.fileExists(atPath: replacement.path))
                session.library.add([root.url])
                try check("Adding the same root does not duplicate it", session.library.folders.count == 1)
                let newVideo = root.url.appendingPathComponent("Episode 20.mp4")
                try FileManager.default.linkItem(at: root.url.appendingPathComponent("Episode 2.mp4"), to: newVideo)
                session.library.refresh(root.id)
                try await wait("Refresh discovers newly added videos") { session.library.children[root.node.id]?.contains { $0.url == newVideo } == true }
                let relocated = directory.appendingPathComponent("Moved tree")
                try FileManager.default.moveItem(at: root.url, to: relocated)
                session.library.relink(root.id, to: relocated)
                try await wait("Relocating a media root updates its queued file paths") { session.queue.items.allSatisfy { $0.url.path.hasPrefix(relocated.path + "/") } && session.queue.currentIndex == 1 && session.currentItem?.url.path.hasPrefix(relocated.path + "/") == true }
                try await wait("Relocated root keeps its expanded branches") { session.library.children[extras]?.count == 1 && session.library.folders[0].expandedPaths.contains("Season 2/Extras") }
                let selected = session.queue.current!
                session.queue.select(session.queue.items[0].id)
                try await wait("Selection changes cannot save another video's checkpoint") { persisted()?.currentID == session.queue.currentID && persisted()?.playback == nil }
                session.select(selected)
                try await wait("Playback and queue selection remain consistent after a switch") { session.loaded && session.currentItem?.id == selected.id && session.queue.currentID == selected.id }
                session.set("pause", true)
            }
        }
    }
    private func write(success: Bool, error: String?) {
        (NSApp.delegate as? AppDelegate)?.testExitStatus = success ? 0 : 1
        var report: [String: Any] = ["success": success, "phase": phase, "checks": checks, "date": ISO8601DateFormatter().string(from: Date())]
        if let error { report["error"] = error }
        do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("\(phase).json"), options: .atomic) }
        catch { NSLog("Could not write workspace test result") }
    }
}
