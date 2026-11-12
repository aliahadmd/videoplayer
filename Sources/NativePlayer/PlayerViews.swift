import SwiftUI
import PlayerCore
import UniformTypeIdentifiers

struct PlayerRootView: View {
    @Bindable var session: PlayerSession
    @State private var jumpText = ""
    @State private var jumpError: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if session.showLibrary && !session.compact && !session.fullscreen.active { LibraryView(session: session).frame(width: 260); Divider() }
                ZStack {
                    Color.black
                    VideoSurface(session: session)
                    if session.loaded && !session.tracks.contains(where: { $0.type == "video" }) {
                        Color.black
                        VStack(spacing: 10) { Text(session.currentItem?.title ?? "").font(.system(size: 20, weight: .medium)).foregroundStyle(.white); Text("Audio playback").font(.system(size: 13)).foregroundStyle(.gray) }.padding(24)
                    }
                    if session.currentItem == nil {
                        VStack(spacing: 18) {
                            Text("A place to press play.").font(.system(size: 25, weight: .medium)).foregroundStyle(.white)
                            Text("Drop a video here, or choose a file.").font(.system(size: 14)).foregroundStyle(.gray)
                            Button("Open File…") { session.perform(.open) }.controlSize(.large).keyboardShortcut("o", modifiers: .command)
                            Button("Open Folder…") { session.perform(.openFolder) }.controlSize(.large)
                            if !session.history.isEmpty {
                                Menu("Open Recent") { ForEach(session.history.prefix(8)) { record in Button(record.url.lastPathComponent) { session.openRecent(record) } } }
                                    .menuStyle(.borderlessButton).frame(width: 160).foregroundStyle(.white)
                            }
                        }.padding(30)
                    } else if !session.loaded {
                        VStack(spacing: 12) {
                            if session.phase == "Opening…" { ProgressView().controlSize(.small) }
                            Text(session.phase).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                            Text(session.currentItem?.title ?? "").font(.system(size: 12)).foregroundStyle(.gray).lineLimit(2)
                            if session.phase != "Opening…" { Button("Play Again") { session.togglePause() } }
                        }.padding(24)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if session.showQueue && !session.fullscreen.active { Divider(); QueueView(session: session).frame(width: 255) }
                else if session.showInspector && !session.fullscreen.active { Divider(); InspectorView(session: session).frame(width: 292) }
            }
            if !session.fullscreen.active { Divider(); bottomChrome }
        }
        .overlay(alignment: .top) {
            if session.fullscreen.active {
                FullscreenHeader(session: session).padding(.top, 48)
                    .environment(\.colorScheme, .dark)
                    .opacity(session.fullscreen.visible ? 1 : 0)
                    .allowsHitTesting(session.fullscreen.visible).accessibilityHidden(!session.fullscreen.visible)
                    .onGeometryChange(for: Double.self, of: { $0.size.height }) { session.fullscreen.topHeight = $0 }
            }
        }
        .overlay(alignment: .bottom) {
            if session.fullscreen.active {
                VStack(spacing: 0) { bottomChrome }.environment(\.colorScheme, .dark)
                    .opacity(session.fullscreen.visible ? 1 : 0)
                    .allowsHitTesting(session.fullscreen.visible).accessibilityHidden(!session.fullscreen.visible)
                    .onGeometryChange(for: Double.self, of: { $0.size.height }) { session.fullscreen.bottomHeight = $0 }
            }
        }
        .overlay(alignment: .leading) {
            if session.fullscreen.active && session.showLibrary {
                LibraryView(session: session).frame(width: 260).padding(.top, session.fullscreen.topHeight).padding(.bottom, session.fullscreen.bottomHeight).environment(\.colorScheme, .dark)
            }
        }
        .overlay(alignment: .trailing) {
            if session.fullscreen.active && (session.showQueue || session.showInspector) {
                Group { if session.showQueue { QueueView(session: session) } else { InspectorView(session: session) } }
                    .frame(width: 292).padding(.top, session.fullscreen.topHeight).padding(.bottom, session.fullscreen.bottomHeight).environment(\.colorScheme, .dark)
            }
        }
        .onDrop(of: [.fileURL, .url], isTargeted: nil) { providers in
            let group = DispatchGroup()
            let collector = DropCollector()
            for (index, provider) in providers.enumerated() {
                group.enter()
                provider.loadObject(ofClass: NSURL.self) { object, _ in
                    if let url = object as? URL { collector.add(url, index: index) }
                    group.leave()
                }
            }
            group.notify(queue: .main) { session.open(collector.urls) }
            return !providers.isEmpty
        }
        .sheet(isPresented: $session.showCommands) { CommandSearchView(session: session) }
        .sheet(isPresented: $session.showJump) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Go to Time").font(.headline)
                TextField("Minutes:seconds or hours:minutes:seconds", text: $jumpText).textFieldStyle(.roundedBorder).onSubmit(jump)
                if let jumpError { Text(jumpError).foregroundStyle(.red).font(.caption) }
                HStack { Button("Cancel") { session.showJump = false }.keyboardShortcut(.cancelAction); Spacer(); Button("Go", action: jump).keyboardShortcut(.defaultAction) }
            }.padding(24).frame(width: 370)
        }
    }
    @ViewBuilder private var bottomChrome: some View {
        if let error = session.errorMessage ?? (session.showLibrary ? nil : session.workspaceSaveError) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.red)
                Text(error).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                if session.errorMessage == nil { Button("Retry Save") { session.saveWorkspace() }.buttonStyle(.link) }
                else { Button { session.errorMessage = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss error") }
            }.padding(12).background(.red.opacity(0.06))
            Divider()
        } else if let notice = session.notice {
            HStack {
                Text(notice).font(.system(size: 12)).foregroundStyle(.secondary)
                if notice.hasPrefix("Resumed") { Button("Start Over") { session.seek(0); session.notice = nil }.buttonStyle(.link) }
                Spacer()
                Button { session.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss message")
            }.padding(.horizontal, 16).padding(.vertical, 8).background(.bar)
            Divider()
        }
        TransportView(session: session)
    }
    private func jump() {
        guard let value = TimeText.parse(jumpText), session.seekable, value <= session.duration || session.duration == 0 else { jumpError = "Enter a valid time within this media file."; return }
        session.seek(value); session.showJump = false; jumpError = nil
    }
}

nonisolated final class DropCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int: URL] = [:]
    func add(_ url: URL, index: Int) { lock.lock(); defer { lock.unlock() }; storage[index] = url }
    var urls: [URL] { lock.lock(); defer { lock.unlock() }; return storage.sorted { $0.key < $1.key }.map(\.value) }
}

struct TransportView: View {
    var session: PlayerSession
    @State private var scrubPosition = 0.0
    @State private var scrubbing = false
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text(TimeText.string(scrubbing ? scrubPosition : session.position)).monospacedDigit().frame(width: 62, alignment: .leading)
                Slider(value: Binding(get: { scrubbing ? scrubPosition : min(session.position, max(session.duration, 1)) }, set: { scrubPosition = $0; if !scrubbing { session.seek($0) } }), in: 0...max(session.duration, 1), onEditingChanged: { editing in
                    if editing { scrubbing = true }
                    else { session.seek(scrubPosition); scrubbing = false }
                    session.fullscreen.setScrubbing(editing)
                }).disabled(!session.loaded || !session.seekable).accessibilityLabel("Playback position").accessibilityValue("\(TimeText.string(session.position)) of \(TimeText.string(session.duration))")
                Text(session.duration > 0 ? "−" + TimeText.string(max(0, session.duration - (scrubbing ? scrubPosition : session.position))) : "—:—").monospacedDigit().frame(width: 70, alignment: .trailing)
            }.font(.system(size: 12)).foregroundStyle(.secondary)
            GeometryReader { geometry in HStack(spacing: 14) {
                Button { session.perform(.mute) } label: { Image(systemName: session.muted || session.volume == 0 ? "speaker.slash" : "speaker.wave.2") }.buttonStyle(.plain).frame(width: 22).help("Mute (M)").accessibilityLabel(session.muted ? "Unmute" : "Mute")
                if geometry.size.width > 600 { Slider(value: Binding(get: { session.volume }, set: { session.set("volume", $0) }), in: 0...100).frame(width: 86).accessibilityLabel("Volume") }
                Spacer(minLength: 12)
                if geometry.size.width > 600 { control(.previous, "backward.end") }
                control(.backward, "gobackward")
                Button { session.perform(.togglePause) } label: { Image(systemName: session.playing ? "pause.fill" : "play.fill").font(.system(size: 21, weight: .medium)).frame(width: 38, height: 30) }.buttonStyle(.plain).help("Play / Pause (Space)").accessibilityLabel(session.playing ? "Pause" : "Play")
                control(.forward, "goforward")
                if geometry.size.width > 600 { control(.next, "forward.end") }
                Spacer(minLength: 12)
                Menu {
                    ForEach([0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 3, 4], id: \.self) { speed in Button(String(format: "%g×", speed)) { session.set("speed", speed) } }
                } label: { Text(String(format: "%g×", session.speed)).monospacedDigit().frame(width: 38) }.menuStyle(.borderlessButton).fixedSize().disabled(!session.loaded).accessibilityLabel("Playback speed")
                control(.fullscreen, "arrow.up.left.and.arrow.down.right")
            }.font(.system(size: 14)).foregroundStyle(.primary) }.frame(height: 30)
        }.padding(.horizontal, 20).padding(.vertical, 13).background(.bar)
            .onChange(of: session.position) { _, value in if !scrubbing { scrubPosition = value } }
    }
    private func control(_ command: PlayerCommand, _ symbol: String) -> some View {
        Button { session.perform(command) } label: { Image(systemName: symbol).frame(width: 24, height: 28) }.buttonStyle(.plain).help("\(command.title)  \(session.shortcut(command))").accessibilityLabel(command.title)
    }
}

private struct FullscreenHeader: View {
    var session: PlayerSession
    var body: some View {
        HStack(spacing: 20) {
            Button { session.perform(.fullscreen) } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }.help("Exit full screen (Esc)").accessibilityLabel("Exit Full Screen")
            Text(session.currentItem?.title ?? "Video Player").font(.system(size: 13, weight: .medium)).lineLimit(1)
            Spacer()
            button(.toggleLibrary, "sidebar.left")
            button(.toggleQueue, "list.bullet")
            button(.toggleInspector, "sidebar.right")
        }.font(.system(size: 14)).buttonStyle(.plain).padding(.horizontal, 24).padding(.vertical, 14).background(.bar)
    }
    private func button(_ command: PlayerCommand, _ symbol: String) -> some View {
        Button { session.perform(command) } label: { Image(systemName: symbol).frame(width: 24, height: 24) }.help(command.title).accessibilityLabel(command.title)
    }
}

struct QueueView: View {
    @Bindable var session: PlayerSession
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Queue").font(.headline); Text("\(session.queue.items.count)").foregroundStyle(.secondary); Spacer(); Menu { Button("Add Files…") { session.openPanel(append: true) }; Button("Save Queue…") { session.saveQueue() } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Queue actions") }.padding(16)
            Divider()
            if session.queue.items.isEmpty { Text("Add files to start a queue.").font(.system(size: 12)).foregroundStyle(.secondary).padding(20); Spacer() }
            else {
                List {
                    ForEach(session.queue.items) { item in
                        Button { session.select(item) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: item.id == session.currentItem?.id ? "play.fill" : "film").font(.system(size: 12)).foregroundStyle(item.id == session.currentItem?.id ? .primary : .secondary).frame(width: 15)
                                VStack(alignment: .leading, spacing: 4) { Text(item.title).font(.system(size: 13, weight: item.id == session.currentItem?.id ? .medium : .regular)).lineLimit(2); Text(item.url.isFileURL ? item.url.deletingLastPathComponent().lastPathComponent : item.url.host ?? "Stream").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .contextMenu {
                            Button("Play") { session.select(item) }
                            Button("Move Up") { session.queue.move(item.id, offset: -1) }
                            Button("Move Down") { session.queue.move(item.id, offset: 1) }
                            if item.url.isFileURL { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } }
                            Divider(); Button("Remove from Queue") { session.remove(item) }
                        }
                    }
                }.listStyle(.sidebar)
            }
            Divider()
            Picker("Repeat", selection: $session.queue.repeatMode) { ForEach(RepeatMode.allCases, id: \.self) { Text($0.title).tag($0) } }.padding(14).font(.system(size: 12))
        }.background(.background)
    }
}

struct CommandSearchView: View {
    @Bindable var session: PlayerSession
    @State private var query = ""
    @FocusState private var focused: Bool
    private var filtered: [PlayerCommand] { PlayerCommand.allCases.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(spacing: 0) {
            TextField("Find a playback command…", text: $query).textFieldStyle(.plain).font(.system(size: 17)).padding(20).focused($focused).onSubmit { if let command = filtered.first { run(command) } }
            Divider()
            List(filtered) { command in
                Button { run(command) } label: { HStack { Text(command.title); Spacer(); Text(session.shortcut(command)).font(.system(size: 12)).foregroundStyle(.secondary) }.padding(.vertical, 5).contentShape(Rectangle()) }.buttonStyle(.plain)
            }.listStyle(.plain)
            Divider()
            HStack { Text("Return runs the first result.").font(.system(size: 12)).foregroundStyle(.secondary); Spacer(); Button("Close") { session.showCommands = false }.keyboardShortcut(.cancelAction) }.padding(14)
        }.frame(width: 480, height: 460).onAppear { focused = true }
    }
    private func run(_ command: PlayerCommand) { session.showCommands = false; session.perform(command) }
}
