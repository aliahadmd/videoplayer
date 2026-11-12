import AppKit
import Foundation
import PlayerCore
import MachO
import MediaPlayer

// Exercises the actual engine and native render surface using generated media.
// Activated explicitly by the QA command line; never uses personal preferences.
final class PlaybackSelfTest {
    private let session: PlayerSession
    private let directory: URL
    private var checks: [String] = []
    init(session: PlayerSession, directory: URL) { self.session = session; self.directory = directory }
    func start() {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("SelfTest.json"))
        Task {
            do {
                try await run()
                write(success: true, error: nil)
            } catch { write(success: false, error: error.localizedDescription) }
            if CommandLine.arguments.contains("--stay-open") { session.showInspector = true }
            else { NSApp.terminate(nil) }
        }
    }
    private func wait(_ title: String, seconds: Double = 10, _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(80)) }
        guard predicate() else { throw EngineError.message("\(title) timed out. State: \(session.phase); position: \(session.position); speed: \(session.speed); engine error: \(session.errorMessage ?? "none")") }
        checks.append(title)
    }
    private func check(_ title: String, _ condition: Bool) throws {
        guard condition else { throw EngineError.message("Failed: \(title). \(session.errorMessage ?? "")") }
        checks.append(title)
    }
    private func checkProperty(_ title: String, name: String, expected: Double) async throws {
        let value = await session.engine?.property(name)
        guard case let .number(actual) = value, abs(actual - expected) < 0.01 else { throw EngineError.message("Engine readback failed: \(title)") }
        checks.append(title)
    }
    private func run() async throws {
        try await wait("Native render context created") { session.renderer != nil }
        if CommandLine.arguments.contains("--hdr-only") {
            session.open([directory.appendingPathComponent("HDR10.mkv")])
            try await wait("HEVC 10-bit source opens") { session.loaded && session.position > 0.2 }
            try check("HDR PQ metadata is recognized", session.values["video-params"]?["gamma"].string == "pq")
            return
        }
        session.open([directory.appendingPathComponent("Sample.mp4")])
        try await wait("H.264/AAC MP4 opens") { session.loaded && session.duration > 10 }
        try await wait("Playback advances") { session.position > 0.5 }
        try check("Playback state matches running decoder", session.playing)
        try check("Playing video prevents display sleep", session.preventsDisplaySleep)
        session.engine?.set("pause", true)
        try await wait("Pause command") { session.paused }
        try check("Pause releases display-sleep assertion", !session.preventsDisplaySleep)
        try check("Initial adjustments produce no command errors", session.errorMessage == nil)
        let seekRevision = session.playbackRevision
        session.seek(3)
        try await wait("Exact seek to 3 seconds") { session.playbackRevision > seekRevision && abs(session.position - 3) < 0.05 }
        let systemPosition = (MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? NSNumber)?.doubleValue ?? -1
        try check("Now Playing timeline follows paused seeking", abs(systemPosition - session.position) < 0.05)
        session.set("speed", 1.5)
        try await wait("Speed selection") { abs(session.speed - 1.5) < 0.01 }
        try await checkProperty("Engine confirms speed", name: "speed", expected: 1.5)
        let beforeStep = session.position
        session.perform(.frameForward)
        try await wait("Forward frame step") { session.position > beforeStep + 0.015 && session.paused }
        session.perform(.frameBackward)
        try await wait("Backward frame step") { abs(session.position - 3) < 0.05 }
        session.attachSubtitle(directory.appendingPathComponent("Styled.ass"))
        try await wait("External ASS subtitle attachment") { session.tracks.contains { $0.type == "sub" && $0.codec == "ass" } }
        if let secondary = session.tracks.first(where: { $0.type == "sub" && $0.codec != "ass" }) {
            session.engine?.set("secondary-sid", String(secondary.id))
            try await wait("Secondary subtitle track selection") { Int(session.finite("secondary-sid")) == secondary.id }
            session.engine?.set("secondary-sid", "no")
        } else { throw EngineError.message("Expected the automatically matched SRT track for dual-subtitle validation") }
        session.set("sub-delay", 0.3)
        try await wait("Subtitle timing adjustment") { abs(session.subtitleDelay - 0.3) < 0.01 }
        try await checkProperty("Engine confirms subtitle delay", name: "sub-delay", expected: 0.3)
        session.set("audio-delay", -0.2)
        try await wait("Audio timing adjustment") { abs(session.audioDelay + 0.2) < 0.01 }
        try await checkProperty("Engine confirms audio delay", name: "audio-delay", expected: -0.2)
        session.set("brightness", 5)
        try await wait("Image adjustment") { session.finite("brightness") == 5 }
        try await checkProperty("Engine confirms brightness", name: "brightness", expected: 5)
        session.resetAdjustments()
        try await wait("Reset restores file defaults") { session.speed == 1 && session.subtitleDelay == 0 && session.audioDelay == 0 && session.finite("brightness") == 0 }
        try await checkProperty("Engine confirms adjustment reset", name: "sub-delay", expected: 0)
        let screenshotRevision = session.playbackRevision
        session.seek(4)
        try await wait("Seek before screenshot") { session.playbackRevision > screenshotRevision && abs(session.position - 4) < 0.05 }
        let screenshot = directory.appendingPathComponent("Rendered-frame.png")
        try? FileManager.default.removeItem(at: screenshot)
        session.engine?.command(["screenshot-to-file", screenshot.path, "subtitles"])
        try await wait("Screenshot written") { (try? Data(contentsOf: screenshot)).flatMap(NSBitmapImageRep.init(data:))?.pixelsWide == 1280 }
        let image = NSBitmapImageRep(data: try Data(contentsOf: screenshot))
        try check("Screenshot has video dimensions", image?.pixelsWide == 1280 && image?.pixelsHigh == 720)
        if let image {
            let samples = stride(from: 50, to: 1200, by: 100).compactMap { image.colorAt(x: $0, y: 200)?.usingColorSpace(.deviceRGB) }
            let range = (samples.map(\.redComponent).max() ?? 0) - (samples.map(\.redComponent).min() ?? 0)
            try check("Rendered frame contains varied image data", range > 0.3)
        }
        session.set("ab-loop-a", 4); session.set("ab-loop-b", 5); session.engine?.set("pause", false)
        try await wait("A–B endpoints set") { session.finite("ab-loop-a") == 4 && session.finite("ab-loop-b") == 5 }
        try await Task.sleep(for: .seconds(2.2))
        try check("A–B repeat remains in interval", session.position >= 3.9 && session.position < 5.2)
        session.perform(.clearLoop)
        session.open([directory.appendingPathComponent("Multi-track.mkv"), directory.appendingPathComponent("VP9.webm")])
        try await wait("Multi-audio MKV opens") { session.loaded && session.tracks.filter { $0.type == "audio" }.count == 2 }
        let audio = session.tracks.filter { $0.type == "audio" }
        let secondAudio = audio[1].id
        session.engine?.set("aid", String(secondAudio))
        try await wait("Audio track switches") { Int(session.finite("aid")) == secondAudio }
        try check("Embedded ASS track discovered", session.tracks.contains { $0.type == "sub" })
        session.seek(max(0, session.duration - 0.2))
        try await wait("End of file advances queue") { session.loaded && session.currentItem?.url.lastPathComponent == "VP9.webm" }
        try await wait("VP9 WebM renders") { session.position > 0.3 }
        session.engine?.set("pause", true)
        try await wait("Pause WebM") { session.paused }
        session.open([directory.appendingPathComponent("HDR10.mkv")])
        try await wait("HEVC 10-bit source opens") { session.loaded && session.currentItem?.url.lastPathComponent == "HDR10.mkv" && session.position > 0.2 }
        try check("HDR PQ metadata is recognized", session.values["video-params"]?["gamma"].string == "pq")
        session.open([directory.appendingPathComponent("AV1.webm")])
        try await wait("AV1 WebM decodes") { session.loaded && session.currentItem?.url.lastPathComponent == "AV1.webm" && session.position > 0.2 }
        session.open([directory.appendingPathComponent("Audio.flac")])
        try await wait("Audio-only FLAC plays") { session.loaded && session.tracks.contains { $0.type == "audio" } && !session.tracks.contains { $0.type == "video" } && session.position > 0.2 }
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--http-test-url"), index + 1 < arguments.count, let url = URL(string: arguments[index + 1]) {
            session.open([url])
            try await wait("Direct HTTP media opens") { session.loaded && session.currentItem?.url == url && session.position > 0.2 }
            session.engine?.set("pause", true)
            try await wait("HTTP media pauses") { session.paused }
            let revision = session.playbackRevision
            session.seek(5)
            try await wait("HTTP range seeking") { session.playbackRevision > revision && abs(session.position - 5) < 0.05 }
        }
        let tlsVerification = await session.engine?.property("options/tls-verify")
        try check("TLS certificate verification is enabled", tlsVerification?.flag == true || tlsVerification?.string == "yes")
        let certificateFile = await session.engine?.property("options/tls-ca-file")
        try check("TLS uses the system CA file", certificateFile?.string == "/etc/ssl/cert.pem")
        if let index = arguments.firstIndex(of: "--https-test-url"), index + 1 < arguments.count, let url = URL(string: arguments[index + 1]) {
            session.open([url])
            try await wait("Trusted HTTPS media opens", seconds: 40) { session.loaded && session.currentItem?.url == url && session.position > 0.2 }
            session.engine?.set("pause", true)
            try await wait("HTTPS media pauses") { session.paused }
        }
        if let index = arguments.firstIndex(of: "--untrusted-https-test-url"), index + 1 < arguments.count, let url = URL(string: arguments[index + 1]) {
            session.open([url])
            try await wait("Untrusted HTTPS certificate is rejected") { !session.loaded && session.errorMessage != nil }
        }
        session.open([directory.appendingPathComponent("Broken.mkv")])
        try await wait("Corrupt media shows recoverable error") { !session.loaded && session.errorMessage != nil }
        session.open([directory.appendingPathComponent("Sample.mp4")])
        try await wait("Player recovers after corrupt input") { session.loaded && session.duration > 10 }
        session.engine?.set("pause", true)
        try await wait("Final pause") { session.paused }
        session.preferences.rememberHistory = true
        let resumeRevision = session.playbackRevision
        session.seek(6)
        try await wait("Seek to resume point") { session.playbackRevision > resumeRevision && abs(session.position - 6) < 0.05 }
        session.set("sub-delay", 0.4)
        try await wait("Set file-specific resume timing") { abs(session.subtitleDelay - 0.4) < 0.01 }
        session.saveProgress()
        try check("Local history captures resume point", session.history.first?.resumePosition ?? 0 > 5.9)
        session.open([directory.appendingPathComponent("Sample.mp4")])
        try await wait("Reopening restores playback position and timing") { session.loaded && abs(session.position - 6) < 0.3 && abs(session.subtitleDelay - 0.4) < 0.01 && session.notice?.hasPrefix("Resumed") == true }
        session.engine?.set("pause", true)
        try await wait("Pause restored file") { session.paused }
        session.preferences.rememberHistory = false; session.savePreferences()
        try check("Disabling history clears local records", session.history.isEmpty)
        session.open([directory.appendingPathComponent("Sample.mp4"), directory.appendingPathComponent("Multi-track.mkv"), directory.appendingPathComponent("VP9.webm")])
        try await wait("Prepare rapid queue-change test") { session.loaded && session.queue.items.count == 3 }
        let choices = session.queue.items
        for index in 0..<30 { session.select(choices[index % choices.count]) }
        session.select(choices[0])
        try await wait("Rapid queue changes settle on the last selected file", seconds: 15) { session.loaded && session.currentItem?.id == choices[0].id && session.values["path"]?.string == choices[0].url.path && session.tracks.filter { $0.type == "audio" }.count == 1 && session.duration > 10 }
        session.engine?.set("pause", true)
        try await wait("Pause after rapid changes") { session.paused }
        session.open([directory.appendingPathComponent("Sample.mp4"), directory.appendingPathComponent("Styled.ass")], append: true)
        try await wait("Appending media and subtitle preserves the current queue") { session.queue.items.count == 4 && session.currentItem?.id == choices[0].id }
        let appended = session.queue.items[3]
        session.select(choices[1])
        try await wait("Existing next file loads before the appended item") { session.loaded && session.currentItem?.id == choices[1].id }
        let existingTracks = await session.engine?.property("track-list")
        try check("Pending subtitle does not attach to an unrelated queue item", existingTracks?.array.filter { $0["type"].string == "sub" }.count == 1)
        session.select(appended)
        try await wait("Appended subtitle attaches to its intended file") { session.loaded && session.currentItem?.id == appended.id && session.tracks.filter { $0.type == "sub" }.count == 2 }
        session.engine?.set("pause", true)
        try await wait("Pause appended file") { session.paused }
        try check("No outstanding playback command error", session.errorMessage == nil)
        for size in [NSSize(width: 760, height: 480), NSSize(width: 1200, height: 720), NSSize(width: 900, height: 600)] {
            session.window?.setContentSize(size)
            try await Task.sleep(for: .milliseconds(150))
        }
        checks.append("Native surface resizes without crashing")
        session.perform(.compactPlayer)
        try check("Compact player uses a floating small window", session.compact && session.floating && (session.window?.frame.width ?? 1000) < 600)
        session.perform(.compactPlayer)
        try check("Compact player restores normal window", !session.compact && !session.floating && (session.window?.frame.width ?? 0) >= 720)
        let originalPanels = (session.showLibrary, session.showQueue, session.showInspector)
        let renderIdentity = session.renderer.map(ObjectIdentifier.init)
        session.showLibrary = true; session.showQueue = true
        session.perform(.fullscreen)
        try await wait("Native full-screen transition completes") { session.fullscreen.active && !session.fullscreen.transitioning && session.window?.styleMask.contains(.fullScreen) == true }
        try check("Full-screen chrome starts visible", session.fullscreen.visible)
        try check("Full screen temporarily tucks away windowed sidebars", !session.showLibrary && !session.showQueue && !session.showInspector)
        try check("Full screen hides the window toolbar", session.window?.toolbar?.isVisible == false)
        try check("Video keeps the same native renderer in full screen", session.renderer.map(ObjectIdentifier.init) == renderIdentity)
        let contentWidth = session.window?.contentView?.bounds.width ?? 0
        try check("Full-screen video spans the content width", abs((session.videoView?.bounds.width ?? 0) - contentWidth) < 2 && contentWidth > 0)
        let frame = session.window?.frame ?? .zero
        try check("Pointer in the measured top bar holds controls visible", session.fullscreen.pointerIsOverControls(NSPoint(x: frame.width / 2, y: frame.height - session.fullscreen.topHeight / 2)))
        try check("Pointer in the measured bottom bar holds controls visible", session.fullscreen.pointerIsOverControls(NSPoint(x: frame.width / 2, y: session.fullscreen.bottomHeight / 2)))
        try check("Pointer in the video center permits auto-hide", !session.fullscreen.pointerIsOverControls(NSPoint(x: frame.width / 2, y: frame.height / 2)))
        try check("Pointer outside the player does not pin controls", !session.fullscreen.pointerIsOverControls(NSPoint(x: -10, y: 20)))
        try await Task.sleep(for: .seconds(3.5))
        try check("Paused full-screen playback keeps controls visible", session.fullscreen.visible && session.paused)
        session.showInspector = true
        try check("Full-screen inspector can open without altering windowed panels", session.showInspector)
        session.perform(.fullscreen)
        try await wait("Leaving full screen restores windowed mode") { !session.fullscreen.active && !session.fullscreen.transitioning && session.window?.styleMask.contains(.fullScreen) == false }
        try check("Leaving full screen restores the toolbar and panels", session.window?.toolbar?.isVisible == true && session.showLibrary && session.showQueue && !session.showInspector)
        session.showLibrary = originalPanels.0; session.showQueue = originalPanels.1; session.showInspector = originalPanels.2
    }
    private func write(success: Bool, error: String?) {
        (NSApp.delegate as? AppDelegate)?.testExitStatus = success ? 0 : 1
        var report: [String: Any] = ["success": success, "checks": checks, "date": ISO8601DateFormatter().string(from: Date()), "engine": "libmpv 0.42.0", "presentation": "OpenGL SDR"]
        report["final_video_parameters"] = ["width": session.values["video-params"]?["w"].number ?? 0, "height": session.values["video-params"]?["h"].number ?? 0, "transfer": session.values["video-params"]?["gamma"].string ?? ""]
        report["hardware_decoder"] = session.values["hwdec-current"]?.string ?? ""
        let frameworkRoot = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks").path + "/"
        var bundledLibraries: [String] = []
        var homebrewLoaded = false
        for index in 0..<_dyld_image_count() {
            guard let name = _dyld_get_image_name(index) else { continue }
            let path = String(cString: name)
            if path.hasPrefix(frameworkRoot) { bundledLibraries.append(URL(fileURLWithPath: path).lastPathComponent) }
            if path.hasPrefix("/opt/homebrew/") { homebrewLoaded = true }
        }
        report["bundled_libraries"] = bundledLibraries.sorted()
        report["homebrew_libraries_loaded"] = homebrewLoaded
        if let error { report["error"] = error }
        do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("SelfTest.json"), options: .atomic) }
        catch { NSLog("Could not write QA result") }
    }
}
