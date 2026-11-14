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
    public static func migrateIfNeeded(from legacyDirectory: URL, to targetDirectory: URL) {
        let manager = FileManager.default
        let files = ["preferences.json", "history.json", "workspace.json", "workspace.backup.json"]
        guard !files.contains(where: { manager.fileExists(atPath: targetDirectory.appendingPathComponent($0).path) }),
              files.contains(where: { manager.fileExists(atPath: legacyDirectory.appendingPathComponent($0).path) }) else { return }
        try? manager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        for name in files {
            let source = legacyDirectory.appendingPathComponent(name)
            let destination = targetDirectory.appendingPathComponent(name)
            guard manager.fileExists(atPath: source.path), !manager.fileExists(atPath: destination.path) else { continue }
            try? manager.copyItem(at: source, to: destination)
        }
    }
}
