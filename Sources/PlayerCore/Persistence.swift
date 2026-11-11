import Foundation

public struct Preferences: Codable, Equatable, Sendable {
    public var rememberHistory = true
    public var resumePlayback = true
    public var autoNext = true
    public var seekSeconds = 5.0
    public var volume = 70.0
    public var hardwareDecoding = true
    public var subtitleFont = "sans-serif"
    public var subtitleSize = 40.0
    public var appearance = "system"
    public var rememberWorkspace = true
    public var shortcuts: [String: String] = [:]
    public init() {}
    private enum CodingKeys: String, CodingKey { case rememberHistory, resumePlayback, autoNext, seekSeconds, volume, hardwareDecoding, subtitleFont, subtitleSize, appearance, shortcuts, rememberWorkspace }
    public init(from decoder: any Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        rememberHistory = try values.decodeIfPresent(Bool.self, forKey: .rememberHistory) ?? rememberHistory
        resumePlayback = try values.decodeIfPresent(Bool.self, forKey: .resumePlayback) ?? resumePlayback
        autoNext = try values.decodeIfPresent(Bool.self, forKey: .autoNext) ?? autoNext
        seekSeconds = try values.decodeIfPresent(Double.self, forKey: .seekSeconds) ?? seekSeconds
        volume = try values.decodeIfPresent(Double.self, forKey: .volume) ?? volume
        hardwareDecoding = try values.decodeIfPresent(Bool.self, forKey: .hardwareDecoding) ?? hardwareDecoding
        subtitleFont = try values.decodeIfPresent(String.self, forKey: .subtitleFont) ?? subtitleFont
        subtitleSize = try values.decodeIfPresent(Double.self, forKey: .subtitleSize) ?? subtitleSize
        appearance = try values.decodeIfPresent(String.self, forKey: .appearance) ?? appearance
        shortcuts = try values.decodeIfPresent([String: String].self, forKey: .shortcuts) ?? shortcuts
        rememberWorkspace = try values.decodeIfPresent(Bool.self, forKey: .rememberWorkspace) ?? rememberWorkspace
    }
}

public struct ResumeRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String { url.absoluteString }
    public var url: URL
    public var bookmark: Data?
    public var position: Double
    public var duration: Double
    public var date: Date
    public var subtitleDelay: Double
    public var audioDelay: Double
    public init(url: URL, bookmark: Data? = nil, position: Double, duration: Double, date: Date = Date(), subtitleDelay: Double = 0, audioDelay: Double = 0) {
        self.url = url; self.bookmark = bookmark; self.position = position; self.duration = duration; self.date = date
        self.subtitleDelay = subtitleDelay; self.audioDelay = audioDelay
    }
    public var resumePosition: Double { position >= 5 && duration > 0 && position < duration - 5 ? position : 0 }
}

public struct DiskStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func read<T: Decodable>(_ type: T.Type, name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    public func write(_ value: some Encodable, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: directory.appendingPathComponent(name), options: .atomic)
    }
    public static func retaining(_ records: [ResumeRecord], replacing record: ResumeRecord, limit: Int = 200) -> [ResumeRecord] {
        Array(([record] + records.filter { $0.id != record.id }).prefix(max(0, limit)))
    }
}
