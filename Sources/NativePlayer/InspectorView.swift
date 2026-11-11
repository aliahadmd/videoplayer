import SwiftUI
import PlayerCore

struct InspectorView: View {
    var session: PlayerSession
    @State private var tab = "Play"
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Inspector").font(.headline); Spacer(); Button { session.showInspector = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Close inspector") }.padding(16)
            Picker("Inspector section", selection: $tab) { ForEach(["Play", "Subs", "Audio", "Video", "Info"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 12).padding(.bottom, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch tab {
                    case "Subs": subtitles
                    case "Audio": audio
                    case "Video": video
                    case "Info": information
                    default: playback
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Button("Reset Current File Adjustments") { session.perform(.resetAdjustments) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary).padding(14).disabled(!session.loaded)
        }.background(.background)
    }
    private var playback: some View {
        Group {
            section("Playback") {
                Picker("Speed", selection: number("speed", fallback: 1)) { ForEach([0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 3, 4], id: \.self) { Text(String(format: "%g×", $0)).tag($0) } }
                HStack { Button("Previous Frame") { session.perform(.frameBackward) }; Button("Next Frame") { session.perform(.frameForward) } }.controlSize(.small)
                Button("Go to Time…") { session.perform(.jumpToTime) }
            }
            section("A–B repeat") {
                LabeledContent("Start", value: loopTime("ab-loop-a"))
                LabeledContent("End", value: loopTime("ab-loop-b"))
                HStack { Button("Set A") { session.perform(.loopA) }; Button("Set B") { session.perform(.loopB) }; Button("Clear") { session.perform(.clearLoop) } }.controlSize(.small)
            }
            if !session.chapters.isEmpty {
                section("Chapters") {
                    ForEach(session.chapters) { chapter in Button { session.seek(chapter.time) } label: { HStack { Text(chapter.title).lineLimit(2); Spacer(); Text(TimeText.string(chapter.time)).monospacedDigit().foregroundStyle(.secondary) } }.buttonStyle(.plain) }
                }
            }
        }.disabled(!session.loaded)
    }
    private var subtitles: some View {
        Group {
            section("Tracks") {
                trackPicker("Primary", type: "sub", property: "sid")
                trackPicker("Secondary", type: "sub", property: "secondary-sid")
                Button("Add Subtitle…") { session.perform(.attachSubtitle) }
            }
            section("Timing and appearance") {
                delay("Delay", property: "sub-delay")
                adjustment("Scale", property: "sub-scale", range: 0.5...3, fallback: 1)
                adjustment("Vertical position", property: "sub-pos", range: 0...100, fallback: 100)
                Text("Positive delay shows subtitles later. ASS subtitles retain their authored styling.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }.disabled(!session.loaded)
    }
    private var audio: some View {
        Group {
            section("Audio") {
                trackPicker("Track", type: "audio", property: "aid")
                delay("A/V delay", property: "audio-delay")
                adjustment("Volume", property: "volume", range: 0...100, fallback: 70)
                Picker("Output", selection: Binding(get: { session.values["audio-device"]?.string ?? "auto" }, set: { session.set("audio-device", $0) })) {
                    ForEach(session.values["audio-device-list"]?.array ?? [], id: \.mapID) { device in Text(device["description"].string).tag(device["name"].string) }
                }
                Text("Playback speed preserves pitch. Output devices follow the system when set to automatic.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }.disabled(!session.loaded)
    }
    private var video: some View {
        Group {
            section("Geometry") {
                Picker("Aspect", selection: number("video-aspect-override", fallback: -1)) { Text("Original").tag(-1.0); Text("16:9").tag(16.0 / 9); Text("4:3").tag(4.0 / 3); Text("2.35:1").tag(2.35) }
                Picker("Rotation", selection: number("video-rotate")) { ForEach([0.0, 90, 180, 270], id: \.self) { Text("\(Int($0))°").tag($0) } }
                adjustment("Zoom", property: "video-zoom", range: -1...2)
                adjustment("Horizontal pan", property: "video-pan-x", range: -1...1)
                adjustment("Vertical pan", property: "video-pan-y", range: -1...1)
            }
            section("Image") {
                adjustment("Brightness", property: "brightness", range: -100...100)
                adjustment("Contrast", property: "contrast", range: -100...100)
                adjustment("Saturation", property: "saturation", range: -100...100)
                adjustment("Gamma", property: "gamma", range: -100...100)
                Toggle("Deinterlace", isOn: Binding(get: { session.values["deinterlace"]?.flag ?? false }, set: { session.set("deinterlace", $0) }))
                Button("Save Screenshot…") { session.perform(.screenshot) }
            }
        }.disabled(!session.loaded)
    }
    private var information: some View {
        Group {
            section("Media") {
                info("File", session.currentItem?.title ?? "No media")
                info("Video", session.values["video-codec"]?.string ?? "—")
                info("Audio", session.values["audio-codec-name"]?.string ?? "—")
                let params = session.values["video-params"] ?? .none
                info("Resolution", "\(Int(params["w"].number)) × \(Int(params["h"].number))")
                info("Source transfer", params["gamma"].string)
                info("Frame rate", String(format: "%.3f fps", session.finite("estimated-vf-fps")))
                info("Duration", TimeText.string(session.duration))
            }
            section("Playback diagnostics") {
                info("Decoder", session.values["hwdec-current"]?.string ?? "Software")
                info("Dropped frames", "\(Int(session.finite("frame-drop-count")))")
                info("Decoder drops", "\(Int(session.finite("decoder-frame-drop-count")))")
                info("Presentation", "OpenGL · SDR / tone mapped")
                info("Engine", "libmpv 0.42.0")
                info("State", session.phase)
                Text("HDR sources are tone mapped to SDR in this rendering path.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) { Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary); content().font(.system(size: 12)) }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func info(_ title: String, _ value: String) -> some View { LabeledContent(title) { Text(value.isEmpty ? "—" : value).foregroundStyle(.secondary).multilineTextAlignment(.trailing).textSelection(.enabled) } }
    private func number(_ key: String, fallback: Double = 0) -> Binding<Double> { Binding(get: { session.values[key]?.number ?? fallback }, set: { session.set(key, $0) }) }
    private func delay(_ title: String, property: String) -> some View {
        HStack { Text(title); Spacer(); TextField("Seconds", value: number(property), format: .number.precision(.fractionLength(2))).textFieldStyle(.roundedBorder).frame(width: 62).accessibilityLabel("\(title) in seconds"); Stepper("\(title) in seconds", value: number(property), step: 0.1).labelsHidden(); Text("s").foregroundStyle(.secondary) }
    }
    private func adjustment(_ title: String, property: String, range: ClosedRange<Double>, fallback: Double = 0) -> some View {
        VStack(spacing: 6) { HStack { Text(title); Spacer(); Text(String(format: "%.2f", session.values[property]?.number ?? fallback)).monospacedDigit().foregroundStyle(.secondary) }; Slider(value: number(property, fallback: fallback), in: range).accessibilityLabel(title) }
    }
    private func trackPicker(_ title: String, type: String, property: String) -> some View {
        Picker(title, selection: Binding(get: { Int(session.values[property]?.number ?? 0) }, set: { session.selectTrack(property, id: $0) })) {
            Text("None").tag(0)
            ForEach(session.tracks.filter { $0.type == type }) { Text($0.label).tag($0.id) }
        }
    }
    private func loopTime(_ key: String) -> String { if case let .number(value) = session.values[key] { TimeText.string(value) } else { "Not set" } }
}

extension EngineValue { nonisolated var mapID: String { self["name"].string } }
