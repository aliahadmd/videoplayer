import Foundation

public enum PlayerCommand: String, Codable, CaseIterable, Identifiable, Sendable {
    case open, openFolder, openURL, addFiles, saveQueue, attachSubtitle, togglePause, stop, backward, forward, longBackward, longForward, previous, next, frameForward, frameBackward, speedUp, speedDown, normalSpeed, volumeUp, volumeDown, mute, fullscreen, alwaysOnTop, compactPlayer, toggleLibrary, toggleQueue, toggleInspector, screenshot, loopA, loopB, clearLoop, subtitleEarlier, subtitleLater, audioEarlier, audioLater, resetAdjustments, jumpToTime, commands
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .open: "Open File…"; case .openFolder: "Open Folder…"; case .openURL: "Open URL…"; case .addFiles: "Add to Queue…"; case .saveQueue: "Save Queue…"; case .attachSubtitle: "Add Subtitle…"
        case .togglePause: "Play / Pause"; case .stop: "Stop"; case .backward: "Seek Backward"; case .forward: "Seek Forward"; case .longBackward: "Seek Backward 1 Minute"; case .longForward: "Seek Forward 1 Minute"
        case .previous: "Previous File"; case .next: "Next File"; case .frameForward: "Next Frame"; case .frameBackward: "Previous Frame"
        case .speedUp: "Increase Speed"; case .speedDown: "Decrease Speed"; case .normalSpeed: "Normal Speed"
        case .volumeUp: "Increase Volume"; case .volumeDown: "Decrease Volume"; case .mute: "Mute / Unmute"
        case .fullscreen: "Toggle Full Screen"; case .alwaysOnTop: "Float on Top"; case .compactPlayer: "Toggle Compact Player"; case .toggleQueue: "Show Queue"; case .toggleInspector: "Show Inspector"
        case .toggleLibrary: "Show Library"
        case .screenshot: "Save Screenshot"; case .loopA: "Set Loop Start"; case .loopB: "Set Loop End"; case .clearLoop: "Clear A–B Loop"
        case .subtitleEarlier: "Subtitles 0.1s Earlier"; case .subtitleLater: "Subtitles 0.1s Later"; case .audioEarlier: "Audio 0.1s Earlier"; case .audioLater: "Audio 0.1s Later"
        case .resetAdjustments: "Reset Current File Adjustments"; case .jumpToTime: "Go to Time…"; case .commands: "Find Command…"
        }
    }
    public var defaultShortcut: String {
        switch self {
        case .open: "cmd+o"; case .openFolder: "cmd+shift+o"; case .openURL: "cmd+l"; case .addFiles: "cmd+shift+a"; case .saveQueue: "cmd+shift+e"; case .attachSubtitle: "cmd+shift+s"
        case .togglePause: "space"; case .stop: "cmd+."; case .backward: "left"; case .forward: "right"; case .longBackward: "shift+left"; case .longForward: "shift+right"
        case .previous: "cmd+left"; case .next: "cmd+right"; case .frameForward: "."; case .frameBackward: ","
        case .speedUp: "]"; case .speedDown: "["; case .normalSpeed: "backspace"
        case .volumeUp: "up"; case .volumeDown: "down"; case .mute: "m"
        case .fullscreen: "cmd+ctrl+f"; case .alwaysOnTop: "cmd+t"; case .compactPlayer: "cmd+shift+m"; case .toggleQueue: "cmd+shift+p"; case .toggleInspector: "cmd+i"
        case .toggleLibrary: "cmd+shift+l"
        case .screenshot: "cmd+s"; case .loopA: "a"; case .loopB: "b"; case .clearLoop: "shift+b"
        case .subtitleEarlier: "z"; case .subtitleLater: "x"; case .audioEarlier: "shift+z"; case .audioLater: "shift+x"
        case .resetAdjustments: "cmd+shift+r"; case .jumpToTime: "cmd+j"; case .commands: "cmd+shift+k"
        }
    }
}

public struct Shortcut: Equatable, Sendable {
    public let key: String
    public let modifiers: Set<String>
    public init?(_ text: String) {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let key = parts.last, !key.isEmpty else { return nil }
        let modifiers = Set(parts.dropLast())
        guard modifiers.isSubset(of: ["cmd", "ctrl", "alt", "shift"]), modifiers.count == parts.count - 1 else { return nil }
        guard key.count == 1 || ["space", "left", "right", "up", "down", "backspace", "return", "escape"].contains(key) else { return nil }
        self.key = key
        self.modifiers = modifiers
    }
    public var canonical: String { (["cmd", "ctrl", "alt", "shift"].filter { modifiers.contains($0) } + [key]).joined(separator: "+") }
    public var display: String {
        let symbols = ["cmd": "⌘", "ctrl": "⌃", "alt": "⌥", "shift": "⇧"]
        let keys = ["space": "Space", "left": "←", "right": "→", "up": "↑", "down": "↓", "backspace": "⌫", "return": "↩", "escape": "Esc"]
        return ["ctrl", "alt", "shift", "cmd"].filter { modifiers.contains($0) }.compactMap { symbols[$0] }.joined() + (keys[key] ?? key.uppercased())
    }
    public static func validate(_ bindings: [String: String]) -> String? {
        var seen: [String: String] = [:]
        for command in PlayerCommand.allCases {
            let value = bindings[command.rawValue] ?? command.defaultShortcut
            if value.isEmpty { continue }
            guard let shortcut = Shortcut(value) else { return "Invalid shortcut for \(command.title). Use a key such as cmd+shift+s or space." }
            if ["cmd+q", "cmd+w", "cmd+,", "cmd+h", "cmd+alt+h", "cmd+m", "cmd+a", "cmd+c", "cmd+v", "cmd+x", "cmd+z", "cmd+shift+z"].contains(shortcut.canonical) { return "\(shortcut.display) is reserved for a standard Mac command." }
            if let other = seen[shortcut.canonical] { return "\(command.title) conflicts with \(other): \(shortcut.display)." }
            seen[shortcut.canonical] = command.title
        }
        return nil
    }
}
