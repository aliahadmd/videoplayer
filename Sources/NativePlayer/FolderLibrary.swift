import AppKit
import Observation
import PlayerCore

private struct FolderScan: Sendable {
    var folder: LibraryFolder?
    var children: [LibraryNode]
}

// A serial actor bounds filesystem work even when many saved branches reopen.
private actor FolderScanner {
    func scan(_ original: LibraryNode, folder: LibraryFolder?) throws -> FolderScan {
        try Task.checkCancellation()
        var folder = folder
        var node = original
        if var root = folder {
            if let bookmark = root.bookmark {
                var stale = false
                if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting], bookmarkDataIsStale: &stale) {
                    root.url = url
                    if stale { root.bookmark = try? url.bookmarkData(options: .withSecurityScope) }
                }
            }
            folder = root; node = root.node
        }
        let scoped = node.url.startAccessingSecurityScopedResource()
        defer { if scoped { node.url.stopAccessingSecurityScopedResource() } }
        return FolderScan(folder: folder, children: try LibraryFiles.readChildren(of: node))
    }
}

@Observable final class FolderLibrary {
    private(set) var folders: [LibraryFolder]
    private(set) var children: [LibraryLocation: [LibraryNode]] = [:]
    private(set) var failures: [LibraryLocation: String] = [:]
    private(set) var loading: Set<LibraryLocation> = []
    var changed: (() -> Void)?
    var reportError: ((String) -> Void)?
    var relocated: ((URL, URL) -> Void)?
    private var refreshedAt = Date.distantPast
    private let scanner = FolderScanner()
    private var tasks: [LibraryLocation: Task<Void, Never>] = [:]
    private var generations: [UUID: UUID] = [:]
    init(folders: [LibraryFolder] = []) { self.folders = folders }

    func add(_ urls: [URL]) {
        for original in urls {
            let url = original.standardizedFileURL.resolvingSymlinksInPath()
            if let existing = folders.first(where: { $0.url == url }) { setExpanded(existing.node, true); refresh(existing.id); continue }
            guard folders.count < 1_000 else { reportError?("The library can remember up to 1,000 root folders."); break }
            let scoped = original.startAccessingSecurityScopedResource()
            let bookmark = try? original.bookmarkData(options: .withSecurityScope)
            if scoped { original.stopAccessingSecurityScopedResource() }
            let folder = LibraryFolder(url: url, bookmark: bookmark)
            folders.append(folder); changed?(); load(folder.node)
        }
    }
    func isExpanded(_ node: LibraryNode) -> Bool { folders.first { $0.id == node.location.rootID }?.expandedPaths.contains(node.location.path) ?? false }
    func setExpanded(_ node: LibraryNode, _ value: Bool) {
        guard let index = folders.firstIndex(where: { $0.id == node.location.rootID }) else { return }
        if value { folders[index].expandedPaths.insert(node.location.path) }
        else { folders[index].expandedPaths.remove(node.location.path) }
        changed?()
        if value { load(node) }
    }
    func load(_ node: LibraryNode) {
        guard children[node.id] == nil, !loading.contains(node.id), folders.contains(where: { $0.id == node.location.rootID }) else { return }
        loading.insert(node.id); failures[node.id] = nil
        let rootID = node.location.rootID
        let generation = generations[rootID] ?? UUID(); generations[rootID] = generation
        let root = node.location.path.isEmpty ? folders.first { $0.id == rootID } : nil
        tasks[node.id] = Task { [weak self, scanner] in
            do {
                let result = try await scanner.scan(node, folder: root)
                guard !Task.isCancelled, let self, self.generations[rootID] == generation else { return }
                if let resolved = result.folder, let index = self.folders.firstIndex(where: { $0.id == rootID }), self.folders[index].url != resolved.url || self.folders[index].bookmark != resolved.bookmark {
                    // Keep any expansion changes made while the folder was being resolved.
                    let previous = self.folders[index].url
                    self.folders[index].url = resolved.url; self.folders[index].bookmark = resolved.bookmark
                    if previous != resolved.url { self.relocated?(previous, resolved.url) }
                    self.changed?()
                }
                self.children[node.id] = result.children
                self.loading.remove(node.id); self.tasks[node.id] = nil
                for child in result.children where child.isFolder && self.isExpanded(child) { self.load(child) }
            } catch {
                guard !Task.isCancelled, let self, self.generations[rootID] == generation else { return }
                self.failures[node.id] = "Folder unavailable. Connect the drive or locate the folder."
                self.loading.remove(node.id); self.tasks[node.id] = nil
            }
        }
    }
    func refresh(_ rootID: UUID) {
        generations[rootID] = UUID()
        for (id, task) in tasks where id.rootID == rootID { task.cancel() }
        tasks = tasks.filter { $0.key.rootID != rootID }
        children = children.filter { $0.key.rootID != rootID }
        failures = failures.filter { $0.key.rootID != rootID }
        loading = loading.filter { $0.rootID != rootID }
        if let root = folders.first(where: { $0.id == rootID }), isExpanded(root.node) { load(root.node) }
    }
    func refreshAll() { refreshedAt = Date(); for root in folders { refresh(root.id) } }
    func refreshIfNeeded() { if Date().timeIntervalSince(refreshedAt) > 30 { refreshAll() } }
    func remove(_ rootID: UUID) {
        folders.removeAll { $0.id == rootID }; refresh(rootID); changed?()
    }
    func locate(_ rootID: UUID) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "Locate this library folder. Its saved subfolder layout will be kept."; panel.prompt = "Locate"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        relink(rootID, to: url)
    }
    func relink(_ rootID: UUID, to url: URL) {
        guard let index = folders.firstIndex(where: { $0.id == rootID }) else { return }
        guard !folders.contains(where: { $0.id != rootID && $0.url == url.standardizedFileURL }) else { reportError?("That folder is already in the library."); return }
        let scoped = url.startAccessingSecurityScopedResource()
        let previous = folders[index].url
        folders[index].url = url.standardizedFileURL
        folders[index].bookmark = try? url.bookmarkData(options: .withSecurityScope)
        if scoped { url.stopAccessingSecurityScopedResource() }
        if previous != folders[index].url { relocated?(previous, folders[index].url) }
        changed?(); refresh(rootID)
    }
    func mediaSiblings(of node: LibraryNode) -> [LibraryNode] {
        let parent = (node.location.path as NSString).deletingLastPathComponent
        return children[LibraryLocation(rootID: node.location.rootID, path: parent)]?.filter { !$0.isFolder } ?? [node]
    }
    func waitForRoot(containing url: URL) async {
        guard let root = folders.first(where: { url.path.hasPrefix($0.url.path + "/") }), let task = tasks[root.node.id] else { return }
        await task.value
    }
    func stop() { tasks.values.forEach { $0.cancel() }; tasks = [:] }
}
