import Foundation

public struct LibraryLocation: Codable, Hashable, Sendable {
    public var rootID: UUID
    public var path: String
    public init(rootID: UUID, path: String = "") { self.rootID = rootID; self.path = path }
    public static func valid(_ path: String) -> Bool {
        !path.hasPrefix("/") && !path.contains("\0") && !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
    }
}

public struct LibraryFolder: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var url: URL
    public var bookmark: Data?
    public var expandedPaths: Set<String>
    public init(url: URL, id: UUID = UUID(), bookmark: Data? = nil, expandedPaths: Set<String> = [""]) {
        self.id = id; self.url = url.standardizedFileURL; self.bookmark = bookmark; self.expandedPaths = expandedPaths
    }
    public var node: LibraryNode { LibraryNode(location: LibraryLocation(rootID: id), url: url, isFolder: true) }
}

public struct LibraryNode: Identifiable, Equatable, Sendable {
    public var location: LibraryLocation
    public var url: URL
    public var isFolder: Bool
    public var id: LibraryLocation { location }
    public var title: String { url.lastPathComponent }
    public init(location: LibraryLocation, url: URL, isFolder: Bool) { self.location = location; self.url = url; self.isFolder = isFolder }
}

public enum LibraryFiles {
    public static func queueWindow(_ nodes: [LibraryNode], selecting location: LibraryLocation, limit: Int = 10_000) -> [LibraryNode] {
        guard limit > 0 else { return [] }
        guard nodes.count > limit, let index = nodes.firstIndex(where: { $0.id == location }) else { return Array(nodes.prefix(limit)) }
        let start = max(0, min(index - limit / 2, nodes.count - limit))
        return Array(nodes[start..<(start + limit)])
    }
    // Each expansion does one shallow read. Never walk links, packages or an entire drive.
    @concurrent public static func children(of node: LibraryNode) async throws -> [LibraryNode] {
        try readChildren(of: node)
    }
    public static func readChildren(of node: LibraryNode) throws -> [LibraryNode] {
        try Task.checkCancellation()
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isPackageKey, .isSymbolicLinkKey]
        let urls = try FileManager.default.contentsOfDirectory(at: node.url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        var result: [LibraryNode] = []
        for url in urls {
            try Task.checkCancellation()
            guard let values = try? url.resourceValues(forKeys: keys), values.isSymbolicLink != true, values.isPackage != true else { continue }
            let folder = values.isDirectory == true
            guard folder || (values.isRegularFile == true && MediaFiles.isMedia(url)) else { continue }
            let path = node.location.path.isEmpty ? url.lastPathComponent : node.location.path + "/" + url.lastPathComponent
            result.append(LibraryNode(location: LibraryLocation(rootID: node.location.rootID, path: path), url: url, isFolder: folder))
        }
        return result.sorted {
            if $0.isFolder != $1.isFolder { return $0.isFolder }
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.url.path < $1.url.path : order == .orderedAscending
        }
    }
}

public struct WorkspaceState: Codable, Equatable, Sendable {
    public var version = 1
    public var folders: [LibraryFolder] = []
    public var queue: [MediaItem] = []
    public var currentID: UUID?
    public var playback: ResumeRecord?
    public var speed = 1.0
    public var repeatMode: RepeatMode = .off
    public var showLibrary = false
    public var sidebar: String?
    public init() {}
    public func validate() throws {
        guard version == 1, folders.count <= 1_000, queue.count <= 10_000,
              Set(folders.map(\.id)).count == folders.count, Set(queue.map(\.id)).count == queue.count,
              folders.allSatisfy({ $0.url.isFileURL && $0.expandedPaths.count <= 50_000 && $0.expandedPaths.allSatisfy(LibraryLocation.valid) }),
              queue.allSatisfy({ ["file", "http", "https", "rtsp", "rtmp"].contains($0.url.scheme?.lowercased() ?? "") }),
              speed.isFinite && (0.25...4).contains(speed) else { throw WorkspaceFailure.invalid }
    }
}

public enum WorkspaceFailure: LocalizedError {
    case invalid, newerVersion
    public var errorDescription: String? {
        switch self {
        case .invalid: "The saved library or queue is unreadable. Its original data has been preserved."
        case .newerVersion: "The saved library was created by a newer version of Video Player. It has not been changed."
        }
    }
}

public struct WorkspaceStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    private func decode(_ data: Data) throws -> WorkspaceState {
        struct Header: Decodable { var version: Int }
        guard data.count <= 16_000_000 else { throw WorkspaceFailure.invalid }
        if try JSONDecoder().decode(Header.self, from: data).version > 1 { throw WorkspaceFailure.newerVersion }
        let state = try JSONDecoder().decode(WorkspaceState.self, from: data)
        try state.validate()
        return state
    }
    public func load() throws -> (state: WorkspaceState, recovered: Bool) {
        let primary = directory.appendingPathComponent("workspace.json")
        let backup = directory.appendingPathComponent("workspace.backup.json")
        if let data = try? Data(contentsOf: primary) {
            do { return (try decode(data), false) }
            catch WorkspaceFailure.newerVersion { throw WorkspaceFailure.newerVersion }
            catch { if let data = try? Data(contentsOf: backup), let state = try? decode(data) { return (state, true) }; throw WorkspaceFailure.invalid }
        }
        if let data = try? Data(contentsOf: backup) { return (try decode(data), true) }
        if FileManager.default.fileExists(atPath: primary.path) || FileManager.default.fileExists(atPath: backup.path) { throw WorkspaceFailure.invalid }
        return (WorkspaceState(), false)
    }
    public func write(_ state: WorkspaceState) throws {
        try state.validate()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let primary = directory.appendingPathComponent("workspace.json")
        if let data = try? Data(contentsOf: primary) {
            do {
                _ = try decode(data)
                try data.write(to: directory.appendingPathComponent("workspace.backup.json"), options: .atomic)
            } catch WorkspaceFailure.newerVersion { throw WorkspaceFailure.newerVersion }
            catch {
                // Preserve unreadable state instead of silently destroying the only copy.
                try data.write(to: directory.appendingPathComponent("workspace-unreadable-\(UUID().uuidString).json"), options: .atomic)
            }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        guard data.count <= 16_000_000 else { throw WorkspaceFailure.invalid }
        try data.write(to: primary, options: .atomic)
        let handle = try FileHandle(forWritingTo: primary)
        defer { try? handle.close() }
        try handle.synchronize()
    }
}

public actor WorkspaceWriter {
    private let store: WorkspaceStore
    private var revision = -1
    public init(directory: URL) { store = WorkspaceStore(directory: directory) }
    public func save(_ state: WorkspaceState, revision: Int, sanitizeBackup: Bool = false) throws {
        guard revision > self.revision else { return }
        try store.write(state)
        if sanitizeBackup { try store.write(state) }
        self.revision = revision
    }
}
