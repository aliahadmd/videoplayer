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

import Foundation
import Testing
@testable import PlayerCore

private func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func libraryPreservesHierarchyAndSkipsLinksPackagesAndHiddenFiles() async throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    for name in ["Season 10", "Season 2", "Sample.app"] { try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true) }
    for name in ["Episode 10.mp4", "Episode 2.mp4", ".secret.mp4", "Notes.txt", "Season 2/Nested.mp4"] { try Data().write(to: root.appendingPathComponent(name)) }
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Cycle"), withDestinationURL: root)
    let folder = LibraryFolder(url: root)
    let children = try await LibraryFiles.children(of: folder.node)
    #expect(children.map(\.title) == ["Season 2", "Season 10", "Episode 2.mp4", "Episode 10.mp4"])
    #expect(!children.contains { $0.title == "Nested.mp4" })
    let nested = try #require(children.first)
    let videos = try await LibraryFiles.children(of: nested)
    #expect(videos.first?.location.path == "Season 2/Nested.mp4")
    #expect(videos.first?.location.rootID == folder.id)
    #expect(try await LibraryFiles.children(of: folder.node).map(\.id) == children.map(\.id))
}

@Test func emptyAndMissingLibraryFoldersHaveDifferentResults() async throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(try await LibraryFiles.children(of: LibraryFolder(url: root).node).isEmpty)
    await #expect(throws: (any Error).self) { try await LibraryFiles.children(of: LibraryFolder(url: root.appendingPathComponent("missing")).node) }
}

@Test func workspaceRoundTripsHierarchyQueueAndPlayback() throws {
    let directory = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: directory) }
    var state = WorkspaceState()
    state.folders = [LibraryFolder(url: directory, expandedPaths: ["", "Season 2", "Season 2/Bonus"])]
    state.queue = [MediaItem(url: directory.appendingPathComponent("clip.mp4"))]
    state.currentID = state.queue[0].id
    state.playback = ResumeRecord(url: state.queue[0].url, position: 7, duration: 14)
    state.showLibrary = true; state.sidebar = "inspector"; state.speed = 1.5
    let store = WorkspaceStore(directory: directory)
    try store.write(state)
    #expect(try store.load().state == state)
    #expect(try store.load().recovered == false)
}

@Test func workspaceRecoversCorruptionAndPreservesNewerDocuments() throws {
    let directory = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WorkspaceStore(directory: directory)
    var first = WorkspaceState(); first.showLibrary = true
    try store.write(first)
    var second = first; second.sidebar = "queue"
    try store.write(second)
    try Data("interrupted".utf8).write(to: directory.appendingPathComponent("workspace.json"))
    #expect(try store.load().state == first)
    #expect(try store.load().recovered)
    let future = Data("{\"version\":999}".utf8)
    try future.write(to: directory.appendingPathComponent("workspace.json"))
    #expect(throws: WorkspaceFailure.self) { try store.load() }
    #expect(throws: WorkspaceFailure.self) { try store.write(first) }
    #expect(WorkspaceFailure.newerVersion.errorDescription?.contains("LiPlayer") == true)
    #expect(try Data(contentsOf: directory.appendingPathComponent("workspace.json")) == future)
}

@Test func olderWorkspaceWritesCannotOverwriteNewerStateAndPrivacyScrubsBackup() async throws {
    let directory = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: directory) }
    let writer = WorkspaceWriter(directory: directory)
    var latest = WorkspaceState(); latest.showLibrary = true
    try await writer.save(latest, revision: 2)
    try await writer.save(WorkspaceState(), revision: 1)
    #expect(try WorkspaceStore(directory: directory).load().state == latest)
    try await writer.save(WorkspaceState(), revision: 3, sanitizeBackup: true)
    let backup = try JSONDecoder().decode(WorkspaceState.self, from: Data(contentsOf: directory.appendingPathComponent("workspace.backup.json")))
    #expect(backup == WorkspaceState())
}

@Test func libraryRejectsTraversalAndOldPreferencesKeepTheirSettings() throws {
    #expect(!LibraryLocation.valid("../Other folder"))
    #expect(!LibraryLocation.valid("/absolute"))
    #expect(LibraryLocation.valid("Season 1/Bonus 中文"))
    var state = WorkspaceState()
    state.folders = [LibraryFolder(url: URL(fileURLWithPath: "/tmp"), expandedPaths: ["../escape"])]
    #expect(throws: WorkspaceFailure.self) { try state.validate() }
    let prefs = try JSONDecoder().decode(Preferences.self, from: Data("{\"volume\":33,\"appearance\":\"dark\",\"shortcuts\":{\"open\":\"cmd+alt+o\"}}".utf8))
    #expect(prefs.volume == 33 && prefs.appearance == "dark" && prefs.shortcuts["open"] == "cmd+alt+o")
    #expect(prefs.rememberWorkspace)
}

@Test func largeFolderQueueKeepsTheSelectedVideoAndDoesNotDropLibraryNodes() {
    let root = UUID()
    let nodes = (0..<10_005).map { index in LibraryNode(location: LibraryLocation(rootID: root, path: "\(index).mp4"), url: URL(fileURLWithPath: "/media/\(index).mp4"), isFolder: false) }
    let selected = nodes[10_004]
    let queue = LibraryFiles.queueWindow(nodes, selecting: selected.id)
    #expect(queue.count == 10_000 && queue.last?.id == selected.id)
    #expect(nodes.count == 10_005)
    #expect(LibraryFiles.queueWindow(nodes, selecting: nodes[0].id).first?.id == nodes[0].id)
}

@Test func workspaceCannotAssociatePlaybackWithAnotherQueueItem() throws {
    let first = MediaItem(url: URL(fileURLWithPath: "/first.mp4"))
    let second = MediaItem(url: URL(fileURLWithPath: "/second.mp4"))
    var state = WorkspaceState(); state.queue = [first, second]; state.currentID = second.id
    state.playback = ResumeRecord(url: first.url, position: 8, duration: 14)
    #expect(throws: WorkspaceFailure.self) { try state.validate() }
    state.playback = ResumeRecord(url: second.url, position: 8, duration: 14)
    try state.validate()
    var queue = PlaybackQueue(); queue.replace([first, second]); queue.select(second.id)
    let moved = MediaItem(url: URL(fileURLWithPath: "/moved.mp4"), id: second.id)
    queue.update(moved)
    #expect(queue.current == moved && queue.currentIndex == 1)
}
