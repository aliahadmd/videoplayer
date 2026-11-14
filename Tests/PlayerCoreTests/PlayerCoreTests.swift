import Foundation
import Testing
@testable import PlayerCore

@Test func queueIdentitySurvivesReordering() throws {
    let items = ["Episode 1.mkv", "Episode 2.mkv", "Episode 3.mkv"].map { MediaItem(url: URL(fileURLWithPath: "/tmp/\($0)")) }
    var queue = PlaybackQueue(); queue.replace(items)
    let selected = queue.select(items[1].id)
    #expect(selected)
    queue.move(items[1].id, offset: -1)
    #expect(queue.current?.id == items[1].id)
    #expect(queue.currentIndex == 0)
    queue.remove(items[1].id)
    #expect(queue.current?.id == items[0].id)
    queue.remove(items[0].id); queue.remove(items[2].id)
    #expect(queue.current == nil)
}

@Test func automaticRepeatDoesNotTrapManualNext() {
    let items = [MediaItem(url: URL(fileURLWithPath: "/a")), MediaItem(url: URL(fileURLWithPath: "/b"))]
    var queue = PlaybackQueue(); queue.replace(items); queue.repeatMode = .item
    let repeated = queue.next(automatic: true)
    let manual = queue.next()
    let end = queue.next()
    #expect(repeated?.id == items[0].id)
    #expect(manual?.id == items[1].id)
    #expect(end == nil)
    queue.repeatMode = .queue
    let wrapped = queue.next(automatic: true)
    let previous = queue.previous()
    #expect(wrapped?.id == items[0].id)
    #expect(previous == nil)
}

@Test func naturalOrderAndMediaTypes() {
    let urls = ["Episode 10.MKV", "Episode 2.mkv", "Episode 1.mkv"].map { URL(fileURLWithPath: "/\($0)") }
    #expect(MediaFiles.naturallySorted(urls).map(\.lastPathComponent) == ["Episode 1.mkv", "Episode 2.mkv", "Episode 10.MKV"])
    #expect(MediaFiles.isMedia(urls[0]))
    #expect(MediaFiles.isSubtitle(URL(fileURLWithPath: "/subtitle.ASS")))
    #expect(!MediaFiles.isMedia(URL(fileURLWithPath: "/notes.txt")))
}

@Test(arguments: [("90", 90.0), ("01:02", 62), ("1:02:03.5", 3723.5), (" 0:05 ", 5)])
func timeParsing(_ value: String, expected: Double) { #expect(TimeText.parse(value) == expected) }

@Test(arguments: ["", "-1", "nan", "inf", "1:60", "1::2", ":5", "1:2:3:4", "1:99:00"])
func rejectsInvalidTimes(_ value: String) { #expect(TimeText.parse(value) == nil) }

@Test func formattingHandlesNonFiniteAndLongMedia() {
    #expect(TimeText.string(3723) == "1:02:03")
    #expect(TimeText.string(-62) == "−1:02")
    #expect(TimeText.string(.nan) == "—:—")
}

@Test func shortcutCanonicalizationAndConflicts() throws {
    #expect(Shortcut("shift+cmd+s")?.canonical == "cmd+shift+s")
    #expect(Shortcut("cmd+cmd+s") == nil)
    #expect(Shortcut("super+s") == nil)
    #expect(Shortcut.validate([:]) == nil)
    #expect(Shortcut.validate([PlayerCommand.open.rawValue: "space"]) != nil)
    #expect(Shortcut.validate([PlayerCommand.open.rawValue: ""]) == nil)
    #expect(Shortcut.validate([PlayerCommand.open.rawValue: "cmd+q"]) != nil)
}

@Test func resumeDoesNotRestartCompletedFilesNearEnd() {
    let url = URL(fileURLWithPath: "/test.mp4")
    #expect(ResumeRecord(url: url, position: 95, duration: 100).resumePosition == 0)
    #expect(ResumeRecord(url: url, position: 4, duration: 100).resumePosition == 0)
    #expect(ResumeRecord(url: url, position: 50, duration: 100).resumePosition == 50)
    #expect(ResumeRecord(url: url, position: 50, duration: 0).resumePosition == 0)
}

@Test func historyIsBoundedAndReplacesFileIdentity() {
    let records = (0..<250).map { ResumeRecord(url: URL(fileURLWithPath: "/\($0).mp4"), position: 20, duration: 100) }
    let replacement = ResumeRecord(url: records[10].url, position: 45, duration: 100)
    let bounded = DiskStore.retaining(records, replacing: replacement)
    #expect(bounded.count == 200)
    #expect(bounded[0].position == 45)
    #expect(bounded.filter { $0.url == replacement.url }.count == 1)
}

@Test func persistenceRoundTripAndCorruption() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = DiskStore(directory: directory)
    var preferences = Preferences(); preferences.rememberHistory = false; preferences.shortcuts["open"] = "cmd+alt+o"
    try store.write(preferences, name: "preferences.json")
    #expect(store.read(Preferences.self, name: "preferences.json") == preferences)
    try Data("corrupt".utf8).write(to: directory.appendingPathComponent("preferences.json"))
    #expect(store.read(Preferences.self, name: "preferences.json") == nil)
}

@Test func folderExpansionDoesNotRecurseOrIncludeDocuments() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory.appendingPathComponent("nested.mp4"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    for name in ["clip10.mp4", "clip2.mp4", "notes.txt", ".hidden.mp4"] { try Data().write(to: directory.appendingPathComponent(name)) }
    let expanded = try await MediaFiles.expand([directory])
    #expect(expanded.map(\.lastPathComponent) == ["clip2.mp4", "clip10.mp4"])
}

@Test func playlistRoundTripAndAddressValidation() throws {
    let urls = [URL(fileURLWithPath: "/Volumes/Media/a movie 中文.mkv"), URL(string: "https://example.com/movie.mp4")!]
    #expect(try Playlist.decode(Playlist.encode(urls)) == urls)
    #expect(throws: (any Error).self) { try Playlist.encode([URL(string: "javascript:alert(1)")!]) }
    #expect(throws: (any Error).self) { try Playlist.decode(Data("{\"version\":99,\"entries\":[]}".utf8)) }
}

@Test func localM3UResolvesRelativeEntriesAndPreservesHLS() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("watch.m3u8")
    try Data("#EXTM3U\nclip1.mp4\nhttps://example.com/clip2.mp4\n".utf8).write(to: url)
    #expect(try Playlist.read(url)?.first == directory.appendingPathComponent("clip1.mp4"))
    try Data("#EXTM3U\n#EXT-X-TARGETDURATION:10\nsegment1.ts\n".utf8).write(to: url)
    #expect(try Playlist.read(url) == nil)
}

@Test func readsCurrentAndLegacyQueueExtensions() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let urls = [URL(fileURLWithPath: "/Volumes/Media/clip1.mkv"), URL(string: "https://example.com/clip2.mp4")!]
    let data = try Playlist.encode(urls)
    let lpqueue = directory.appendingPathComponent("Watch.lpqueue")
    let vpqueue = directory.appendingPathComponent("Legacy.vpqueue")
    try data.write(to: lpqueue)
    try data.write(to: vpqueue)
    #expect(try Playlist.read(lpqueue) == urls)
    #expect(try Playlist.read(vpqueue) == urls)
}

@Test func diskStoreMigratesLegacySupportFilesWithoutOverwriting() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let legacy = root.appendingPathComponent("VideoPlayer")
    let target = root.appendingPathComponent("LiPlayer")
    DiskStore.migrateIfNeeded(from: legacy, to: target)
    #expect(!FileManager.default.fileExists(atPath: target.path))

    let legacyStore = DiskStore(directory: legacy)
    var prefs = Preferences(); prefs.volume = 42; prefs.appearance = "dark"
    try legacyStore.write(prefs, name: "preferences.json")
    let record = ResumeRecord(url: URL(fileURLWithPath: "/sample.mp4"), position: 15, duration: 90)
    try legacyStore.write([record], name: "history.json")

    DiskStore.migrateIfNeeded(from: legacy, to: target)
    let migratedStore = DiskStore(directory: target)
    #expect(migratedStore.read(Preferences.self, name: "preferences.json") == prefs)
    #expect(migratedStore.read([ResumeRecord].self, name: "history.json") == [record])
    #expect(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("preferences.json").path))

    var updated = prefs; updated.volume = 85
    try migratedStore.write(updated, name: "preferences.json")
    DiskStore.migrateIfNeeded(from: legacy, to: target)
    #expect(migratedStore.read(Preferences.self, name: "preferences.json")?.volume == 85)
}
