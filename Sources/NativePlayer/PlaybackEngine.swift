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
import CMPV
import os

nonisolated enum EngineValue: Sendable {
    case none, string(String), number(Double), flag(Bool), array([EngineValue]), map([String: EngineValue])
    var string: String { if case let .string(value) = self { value } else { "" } }
    var number: Double { switch self { case let .number(value): value; case let .flag(value): value ? 1 : 0; default: 0 } }
    var flag: Bool { switch self { case let .flag(value): value; case let .number(value): value != 0; default: false } }
    var array: [EngineValue] { if case let .array(value) = self { value } else { [] } }
    var map: [String: EngineValue] { if case let .map(value) = self { value } else { [:] } }
    subscript(_ key: String) -> EngineValue { map[key] ?? .none }
    init(_ node: mpv_node) {
        switch node.format {
        case MPV_FORMAT_STRING: self = node.u.string.map { .string(String(cString: $0)) } ?? .none
        case MPV_FORMAT_FLAG: self = .flag(node.u.flag != 0)
        case MPV_FORMAT_INT64: self = .number(Double(node.u.int64))
        case MPV_FORMAT_DOUBLE: self = .number(node.u.double_)
        case MPV_FORMAT_NODE_ARRAY, MPV_FORMAT_NODE_MAP:
            guard let list = node.u.list?.pointee, list.num >= 0, list.num < 100_000, let values = list.values else { self = .none; return }
            if node.format == MPV_FORMAT_NODE_ARRAY {
                self = .array((0..<Int(list.num)).map { EngineValue(values[$0]) })
            } else {
                var object: [String: EngineValue] = [:]
                if let keys = list.keys { for index in 0..<Int(list.num) { if let key = keys[index] { object[String(cString: key)] = EngineValue(values[index]) } } }
                self = .map(object)
            }
        default: self = .none
        }
    }
}

nonisolated enum EngineEvent: Sendable {
    case property(String, EngineValue), refreshed(UUID, String, EngineValue), registered(Int64, UUID), loadFailed(UUID, String), started(Int64), loaded, restarted, screenshotWritten(String), ended(Int64, Int32, String?), error(String)
}

// The C handle is thread-safe; all control/event access is serialized on queue.
// The render API has its own independent serial queue and is released first.
nonisolated final class PlaybackEngine: @unchecked Sendable {
    let handle: OpaquePointer
    private let queue = DispatchQueue(label: "app.liplayer.engine", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.aliahad.liplayer", category: "playback")
    private var timer: DispatchSourceTimer?
    private var stopped = false
    private var requestID: UInt64 = 0
    private var requests: [UInt64: String] = [:]
    private var screenshotRequests: [UInt64: String] = [:]
    private var loadRequests: [UInt64: UUID] = [:]
    private var propertyRequests: [UInt64: (UUID, String)] = [:]
    private var reads: [UInt64: @Sendable (EngineValue) -> Void] = [:]
    private var observedProperties: [String] = []
    private let receive: @Sendable ([EngineEvent]) -> Void

    init(receive: @escaping @Sendable ([EngineEvent]) -> Void) throws {
        guard let handle = mpv_create() else { throw EngineError.message("Could not create the playback engine.") }
        self.handle = handle
        self.receive = receive
        // The bundled OpenSSL must use the system CA file rather than its Homebrew build prefix.
        let options = ["config": "no", "terminal": "no", "vo": "libmpv", "hwdec": "videotoolbox", "idle": "yes", "keep-open": "no", "input-default-bindings": "no", "input-vo-keyboard": "no", "osd-level": "0", "load-scripts": "no", "ytdl": "no", "sub-auto": "exact", "audio-file-auto": "exact", "audio-pitch-correction": "yes", "screenshot-format": "png", "target-colorspace-hint": "no", "target-trc": "srgb", "target-prim": "bt.709", "tls-verify": "yes", "tls-ca-file": "/etc/ssl/cert.pem"]
        for (name, value) in options { mpv_set_option_string(handle, name, value) }
        let status = mpv_initialize(handle)
        guard status >= 0 else { mpv_terminate_destroy(handle); throw EngineError.message(String(cString: mpv_error_string(status))) }
        let properties = ["time-pos", "duration", "pause", "volume", "mute", "speed", "track-list", "chapter-list", "aid", "sid", "secondary-sid", "chapter", "audio-delay", "sub-delay", "sub-scale", "sub-pos", "brightness", "contrast", "saturation", "gamma", "video-zoom", "video-pan-x", "video-pan-y", "video-rotate", "video-aspect-override", "deinterlace", "hwdec-current", "video-codec", "audio-codec-name", "video-params", "video-out-params", "decoder-frame-drop-count", "frame-drop-count", "estimated-vf-fps", "demuxer-cache-state", "paused-for-cache", "seekable", "media-title", "path", "ab-loop-a", "ab-loop-b", "audio-device-list", "audio-device", "audio-params", "eof-reached", "seeking", "sub-text"]
        observedProperties = properties
        for (index, name) in properties.enumerated() { mpv_observe_property(handle, UInt64(index + 1), name, MPV_FORMAT_NODE) }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(25))
        timer.setEventHandler { [weak self] in self?.drain() }
        self.timer = timer
        timer.resume()
    }

    func command(_ arguments: [String], itemID: UUID? = nil) {
        queue.async { [self] in
            guard !stopped else { return }
            requestID &+= 1
            let strings = arguments.map { strdup($0) }
            defer { strings.forEach { free($0) } }
            var pointers: [UnsafePointer<CChar>?] = strings.map { pointer in pointer.map { UnsafePointer<CChar>($0) } } + [nil]
            let status = mpv_command_async(handle, requestID, &pointers)
            if status < 0 {
                let message = String(cString: mpv_error_string(status))
                receive([itemID.map { .loadFailed($0, message) } ?? .error(message)])
            }
            else { requests[requestID] = arguments.first == "set" ? "Set \(arguments.dropFirst().first ?? "property")" : (arguments.first ?? "Command") }
            if status >= 0, let itemID { loadRequests[requestID] = itemID }
            if status >= 0, arguments.first == "screenshot-to-file", arguments.count > 1 { screenshotRequests[requestID] = arguments[1] }
        }
    }
    func refresh(itemID: UUID) {
        queue.async { [self] in
            guard !stopped else { return }
            for name in observedProperties {
                requestID &+= 1
                let status = mpv_get_property_async(handle, requestID, name, MPV_FORMAT_NODE)
                if status >= 0 { propertyRequests[requestID] = (itemID, name) }
            }
        }
    }
    func set(_ name: String, _ value: String) { command(["set", name, value]) }
    static func normalized(_ name: String, _ value: Double) -> Double {
        ["brightness", "contrast", "saturation", "gamma", "video-rotate"].contains(name) ? value.rounded() : value
    }
    func set(_ name: String, _ value: Double) {
        let value = Self.normalized(name, value)
        set(name, value.rounded() == value && abs(value) < Double(Int.max / 2) ? String(Int(value)) : String(value))
    }
    func set(_ name: String, _ value: Bool) { set(name, value ? "yes" : "no") }
    func property(_ name: String) async -> EngineValue {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard !stopped else { continuation.resume(returning: .none); return }
                requestID &+= 1
                let status = mpv_get_property_async(handle, requestID, name, MPV_FORMAT_NODE)
                if status < 0 { continuation.resume(returning: .none) }
                else { reads[requestID] = { continuation.resume(returning: $0) } }
            }
        }
    }

    private func drain() {
        guard !stopped else { return }
        var events: [EngineEvent] = []
        while let pointer = mpv_wait_event(handle, 0) {
            let event = pointer.pointee
            if event.event_id == MPV_EVENT_NONE { break }
            switch event.event_id {
            case MPV_EVENT_PROPERTY_CHANGE:
                guard let property = event.data?.assumingMemoryBound(to: mpv_event_property.self).pointee, let name = property.name else { continue }
                let value = property.format == MPV_FORMAT_NODE ? property.data.map { EngineValue($0.assumingMemoryBound(to: mpv_node.self).pointee) } ?? .none : .none
                events.append(.property(String(cString: name), value))
            case MPV_EVENT_START_FILE:
                if let start = event.data?.assumingMemoryBound(to: mpv_event_start_file.self).pointee { events.append(.started(start.playlist_entry_id)) }
            case MPV_EVENT_FILE_LOADED: events.append(.loaded)
            case MPV_EVENT_PLAYBACK_RESTART: events.append(.restarted)
            case MPV_EVENT_END_FILE:
                if let end = event.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee {
                    events.append(.ended(end.playlist_entry_id, Int32(end.reason.rawValue), end.error < 0 ? String(cString: mpv_error_string(end.error)) : nil))
                }
            case MPV_EVENT_COMMAND_REPLY:
                let name = requests.removeValue(forKey: event.reply_userdata) ?? "Command"
                let screenshotPath = screenshotRequests.removeValue(forKey: event.reply_userdata)
                let itemID = loadRequests.removeValue(forKey: event.reply_userdata)
                if event.error < 0 {
                    let message = "\(name): \(String(cString: mpv_error_string(event.error)))"
                    events.append(itemID.map { .loadFailed($0, message) } ?? .error(message))
                }
                else if let itemID, let result = event.data?.assumingMemoryBound(to: mpv_event_command.self).pointee.result {
                    if case let .number(id) = EngineValue(result)["playlist_entry_id"] { events.append(.registered(Int64(id), itemID)) }
                    else { events.append(.loadFailed(itemID, "The engine did not identify the opened media.")) }
                }
                else if let screenshotPath { events.append(.screenshotWritten(screenshotPath)) }
            case MPV_EVENT_GET_PROPERTY_REPLY:
                let property = event.data?.assumingMemoryBound(to: mpv_event_property.self).pointee
                let value = property?.format == MPV_FORMAT_NODE ? property?.data.map { EngineValue($0.assumingMemoryBound(to: mpv_node.self).pointee) } ?? .none : .none
                if let read = reads.removeValue(forKey: event.reply_userdata) { read(value) }
                else if let (itemID, name) = propertyRequests.removeValue(forKey: event.reply_userdata) { events.append(.refreshed(itemID, name, value)) }
            default: break
            }
        }
        if !events.isEmpty { receive(events) }
    }

    func shutdown(completion: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            guard !stopped else { completion(); return }
            stopped = true
            timer?.cancel(); timer = nil
            reads.values.forEach { $0(.none) }; reads.removeAll()
            mpv_terminate_destroy(handle)
            logger.info("Playback engine stopped")
            completion()
        }
    }
}

nonisolated enum EngineError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case let .message(text): text } }
}
