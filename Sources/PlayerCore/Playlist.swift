import Foundation

public enum Playlist {
    private struct Document: Codable { let version: Int; let entries: [URL] }
    public enum Failure: LocalizedError { case invalid
        public var errorDescription: String? { "This queue is invalid, uses an unsupported version, or contains unsupported addresses." }
    }
    public static func encode(_ urls: [URL]) throws -> Data {
        guard urls.count <= 10_000, urls.allSatisfy(valid) else { throw Failure.invalid }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Document(version: 1, entries: urls))
    }
    public static func decode(_ data: Data) throws -> [URL] {
        guard data.count <= 8_000_000 else { throw Failure.invalid }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.version == 1, document.entries.count <= 10_000, document.entries.allSatisfy(valid) else { throw Failure.invalid }
        return document.entries
    }
    public static func read(_ url: URL) throws -> [URL]? {
        guard url.isFileURL else { return nil }
        if ["lpqueue", "vpqueue"].contains(url.pathExtension.lowercased()) { return try decode(Data(contentsOf: url)) }
        guard ["m3u", "m3u8"].contains(url.pathExtension.lowercased()) else { return nil }
        let data = try Data(contentsOf: url)
        guard data.count <= 8_000_000, let text = String(data: data, encoding: .utf8) else { throw Failure.invalid }
        // HLS is one media source, not a queue of individual segments.
        if text.contains("#EXT-X-") { return nil }
        let entries = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }.map { line in
            if let address = URL(string: line), address.scheme != nil { return address }
            return URL(fileURLWithPath: line, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
        }
        guard entries.count <= 10_000, entries.allSatisfy(valid) else { throw Failure.invalid }
        return entries
    }
    private static func valid(_ url: URL) -> Bool { ["file", "http", "https", "rtsp", "rtmp"].contains(url.scheme?.lowercased() ?? "") && !url.absoluteString.contains("\0") }
}
