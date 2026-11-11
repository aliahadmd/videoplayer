import Foundation

public struct MediaItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public var bookmark: Data?
    public init(url: URL, id: UUID = UUID(), bookmark: Data? = nil) {
        self.id = id
        self.url = url.isFileURL ? url.standardizedFileURL : url
        self.bookmark = bookmark
    }
    public var title: String { url.isFileURL ? url.lastPathComponent : (url.host ?? url.absoluteString) }
}

public enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case off, queue, item
    public var title: String { switch self { case .off: "Off"; case .queue: "Queue"; case .item: "Current file" } }
}

public struct PlaybackQueue: Sendable {
    public private(set) var items: [MediaItem] = []
    public private(set) var currentID: UUID?
    public var repeatMode: RepeatMode = .off
    public init() {}
    public var currentIndex: Int? { items.firstIndex { $0.id == currentID } }
    public var current: MediaItem? { currentIndex.map { items[$0] } }
    public mutating func replace(_ items: [MediaItem]) {
        self.items = items
        currentID = items.first?.id
    }
    public mutating func append(_ items: [MediaItem]) {
        self.items.append(contentsOf: items)
        if currentID == nil { currentID = self.items.first?.id }
    }
    @discardableResult public mutating func select(_ id: UUID) -> Bool {
        guard items.contains(where: { $0.id == id }) else { return false }
        currentID = id
        return true
    }
    public func followingIndex(automatic: Bool) -> Int? {
        guard let index = currentIndex else { return items.isEmpty ? nil : 0 }
        if automatic && repeatMode == .item { return index }
        if index + 1 < items.count { return index + 1 }
        return repeatMode == .queue ? 0 : nil
    }
    @discardableResult public mutating func next(automatic: Bool = false) -> MediaItem? {
        guard let index = followingIndex(automatic: automatic) else { return nil }
        currentID = items[index].id
        return items[index]
    }
    @discardableResult public mutating func previous() -> MediaItem? {
        guard let index = currentIndex, index > 0 else { return nil }
        currentID = items[index - 1].id
        return items[index - 1]
    }
    public mutating func remove(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: index)
        if currentID == id { currentID = items.isEmpty ? nil : items[min(index, items.count - 1)].id }
    }
    public mutating func move(_ id: UUID, offset: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let destination = max(0, min(items.count - 1, index + offset))
        guard index != destination else { return }
        let item = items.remove(at: index)
        items.insert(item, at: destination)
    }
    public mutating func update(_ item: MediaItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }
}

public enum MediaFiles {
    public static let videoExtensions: Set<String> = ["mp4", "m4v", "mkv", "webm", "mov", "avi", "wmv", "flv", "ts", "m2ts", "mts", "mpeg", "mpg", "vob", "ogv", "3gp", "mxf", "y4m"]
    public static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "flac", "wav", "aiff", "aif", "ogg", "opus", "wma", "ape", "alac", "mka"]
    public static let subtitleExtensions: Set<String> = ["srt", "ass", "ssa", "vtt", "sub", "idx", "sup", "smi", "sami", "lrc"]
    public static func isSubtitle(_ url: URL) -> Bool { subtitleExtensions.contains(url.pathExtension.lowercased()) }
    public static func isMedia(_ url: URL) -> Bool { videoExtensions.union(audioExtensions).contains(url.pathExtension.lowercased()) }
    public static func naturallySorted(_ urls: [URL]) -> [URL] {
        urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
    // Only immediate children of explicitly selected folders are enumerated.
    @concurrent public static func expand(_ urls: [URL]) async throws -> [URL] {
        var result: [URL] = []
        for url in urls {
            try Task.checkCancellation()
            guard url.isFileURL else { result.append(url); continue }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                result += naturallySorted(children.filter { isMedia($0) && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true })
            } else if let entries = try Playlist.read(url) { result += entries }
            else { result.append(url) }
        }
        return result
    }
}

public enum TimeText {
    public static func string(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "—:—" }
        let value = Int(min(abs(seconds), Double(Int.max / 2)))
        let sign = seconds < 0 ? "−" : ""
        return value >= 3600 ? String(format: "%@%d:%02d:%02d", sign, value / 3600, value / 60 % 60, value % 60) : String(format: "%@%d:%02d", sign, value / 60, value % 60)
    }
    public static func parse(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        let numbers = parts.compactMap { Double($0) }
        guard numbers.count == parts.count, numbers.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        if numbers.count > 1 && numbers.dropFirst().contains(where: { $0 >= 60 }) { return nil }
        return numbers.reduce(0) { $0 * 60 + $1 }
    }
}
