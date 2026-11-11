import SwiftUI
import PlayerCore

struct LibraryView: View {
    var session: PlayerSession
    @State private var selection: LibraryLocation?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Library").font(.headline)
                Spacer()
                Button { session.perform(.openFolder) } label: { Image(systemName: "folder.badge.plus") }.buttonStyle(.plain).help("Open Folder…").accessibilityLabel("Add library folder")
                Menu {
                    Button("Add Folder…") { session.perform(.openFolder) }
                    Button("Refresh All Folders") { session.library.refreshAll() }.disabled(session.library.folders.isEmpty)
                    Button("Hide Library") { session.showLibrary = false }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Library actions")
            }.padding(16)
            Divider()
            if session.library.folders.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Keep your video folders here.").font(.system(size: 13, weight: .medium))
                    Text("Browse subfolders without moving or copying your files.").font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("Open Folder…") { session.perform(.openFolder) }
                }.padding(18)
                Spacer()
            } else {
                List(selection: $selection) {
                    ForEach(session.library.folders) { folder in LibraryRow(node: folder.node, session: session) }
                }.listStyle(.sidebar).accessibilityLabel("Folder library")
                    .onKeyPress(.return) {
                        guard let selection else { return .ignored }
                        let nodes = session.library.folders.map(\.node) + session.library.children.values.flatMap { $0 }
                        guard let node = nodes.first(where: { $0.id == selection }) else { return .ignored }
                        if node.isFolder { session.library.setExpanded(node, !session.library.isExpanded(node)) }
                        else { session.playLibraryNode(node) }
                        return .handled
                    }
            }
            Divider()
            HStack(alignment: .top, spacing: 8) {
                if let error = session.workspaceSaveError {
                    Text(error).foregroundStyle(.red)
                    Button("Retry") { session.saveWorkspace() }.buttonStyle(.link)
                } else {
                    Text(!session.preferences.rememberWorkspace ? "Session saving is off" : session.workspaceSaving ? "Saving…" : "Saved on this Mac").foregroundStyle(.secondary)
                }
            }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).padding(14)
        }.background(.background)
    }
}

private struct LibraryRow: View {
    let node: LibraryNode
    var session: PlayerSession
    private var library: FolderLibrary { session.library }
    var body: some View {
        Group {
            if node.isFolder {
                DisclosureGroup(isExpanded: Binding(get: { library.isExpanded(node) }, set: { library.setExpanded(node, $0) })) {
                    if library.loading.contains(node.id) {
                        HStack { ProgressView().controlSize(.mini); Text("Loading…").foregroundStyle(.secondary) }.font(.system(size: 12)).padding(.vertical, 6)
                    } else if let failure = library.failures[node.id] {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(failure).foregroundStyle(.secondary)
                            HStack { Button("Refresh") { library.refresh(node.location.rootID) }; Button("Locate Root…") { library.locate(node.location.rootID) } }.controlSize(.small)
                        }.font(.system(size: 12)).padding(.vertical, 6)
                    } else if let children = library.children[node.id] {
                        if children.isEmpty { Text("No media or subfolders.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 6) }
                        ForEach(children) { child in LibraryRow(node: child, session: session) }
                    }
                } label: {
                    Label(node.title, systemImage: "folder").font(.system(size: 13)).lineLimit(1).help(node.url.path)
                }.contextMenu {
                    Button("Refresh Folder") { library.refresh(node.location.rootID) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
                    if node.location.path.isEmpty {
                        Button("Locate Folder…") { library.locate(node.location.rootID) }
                        Divider()
                        Button("Remove from Library") { library.remove(node.location.rootID) }
                    }
                }.onAppear { if library.isExpanded(node) { library.load(node) } }
            } else {
                Button { session.playLibraryNode(node) } label: {
                    Label(node.title, systemImage: session.currentItem?.url == node.url ? "play.fill" : MediaFiles.videoExtensions.contains(node.url.pathExtension.lowercased()) ? "film" : "waveform")
                        .font(.system(size: 13, weight: session.currentItem?.url == node.url ? .medium : .regular)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4).contentShape(Rectangle())
                }.buttonStyle(.plain).help(node.url.path).accessibilityLabel("Play \(node.title)")
                    .contextMenu {
                        Button("Play") { session.playLibraryNode(node) }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
                    }
            }
        }.tag(node.id)
    }
}
