import AppKit

// MARK: - Sidebar File Browser
//
// A lightweight, lazy file tree pinned to the left edge of the editor window.
//
// Design goals (all in service of the "instant open / 秒开" contract):
//   • It only *lists* a directory — it never scans or indexes anything up
//     front. When a document opens, we asynchronously list that document's
//     directory in the background; the editor's own open path is untouched.
//   • Subfolders are loaded lazily, one level at a time, only when the user
//     expands them — so a folder with thousands of files stays cheap.
//   • It shows only the formats Edmund can actually open (markdown family +
//     plain text) plus folders, so it never becomes a generic file manager.
//   • Clicking a file routes through the same `NSDocumentController.openDocument`
//     the app already uses — no new open path, no extra cost.

/// One row in the sidebar tree. Either a folder (expandable, lazily loaded
/// children) or a file (openable).
final class SidebarNode {
    enum Kind {
        case folder(URL)
        case file(URL)
    }
    let kind: Kind
    let displayName: String

    /// Lazily loaded folder children. `nil` = not loaded yet (shows a single
    /// "loading" placeholder row so expansion gives immediate feedback).
    var children: [SidebarNode]?
    /// Folder rows get a disclosure triangle only once they've actually got
    /// children; scanning happens on first expansion.
    var isLoading = false

    init(kind: Kind, displayName: String) {
        self.kind = kind
        self.displayName = displayName
    }

    var url: URL? {
        switch kind {
        case .folder(let u), .file(let u): return u
        }
    }
    var isFolder: Bool {
        if case .folder = kind { return true }
        return false
    }
}

/// The sidebar panel: a scroll view wrapping an `NSOutlineView` that shows the
/// opened document's directory tree.
final class FileSidebar: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {

    /// Called when the user clicks an openable file row.
    var onOpenFile: ((URL) -> Void)?

    private let outline = NSOutlineView()
    private let scroll = NSScrollView()

    /// Root nodes: the current document's directory (one root folder, but kept
    /// as an array so a future multi-root vault is a drop-in).
    private var roots: [SidebarNode] = []

    private static let editableExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd",
        "txt", "text", "mdx", "mmd",
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        let column = NSTableColumn(identifier: .init("name"))
        column.title = "文件"
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowHeight = 22
        outline.indentationPerLevel = 14
        outline.autoresizesOutlineColumn = true
        outline.dataSource = self
        outline.delegate = self
        outline.backgroundColor = .clear
        outline.selectionHighlightStyle = .sourceList
        outline.style = .sourceList
        outline.target = self
        outline.action = #selector(openClickedRow(_:))
        outline.doubleAction = #selector(openClickedRow(_:))

        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Public API

    /// Points the sidebar at a document's directory and kicks off an async
    /// listing. Called on open (and on "save as", which may move the file).
    func showDirectory(_ directory: URL?) {
        guard let directory else {
            roots = []
            outline.reloadData()
            return
        }
        // Swap the whole tree; the root folder is expanded with its children
        // loaded asynchronously.
        let root = SidebarNode(kind: .folder(directory),
                               displayName: directory.lastPathComponent)
        root.children = []
        roots = [root]
        outline.reloadData()
        outline.expandItem(root)

        loadChildren(of: root, in: directory)
    }

    // MARK: - Async directory listing

    /// Background-lists a folder's openable entries, then reloads the row on
    /// the main actor. Never touches the editor's open path.
    private func loadChildren(of node: SidebarNode, in dirURL: URL) {
        node.isLoading = true
        // A placeholder row makes expansion feel instant even for slow mounts.
        node.children = [SidebarNode(kind: .folder(dirURL),
                                     displayName: "加载中…")]
        outline.reloadItem(node, reloadChildren: true)
        // Show the placeholder before the background work, then replace it.
        DispatchQueue.main.async { [weak self, weak node] in
            guard let self, let node else { return }
            self.loadChildrenAsync(of: node, in: dirURL)
        }
    }

    private func loadChildrenAsync(of node: SidebarNode, in dirURL: URL) {
        // The actual scan on a background queue; cheap for normal folders,
        // still non-blocking for huge ones.
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak node] in
            let entries = Self.listOpenableEntries(in: dirURL)
            DispatchQueue.main.async {
                guard let self, let node else { return }
                node.children = entries
                node.isLoading = false
                self.outline.reloadItem(node, reloadChildren: true)
            }
        }
    }

    /// Returns child nodes (folders first, then files), filtering to formats
    /// Edmund can open. Hidden files/directories are skipped.
    private static func listOpenableEntries(in dirURL: URL) -> [SidebarNode] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return [] }

        var folders: [SidebarNode] = []
        var files: [SidebarNode] = []
        for url in urls {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    folders.append(SidebarNode(kind: .folder(url),
                                               displayName: url.lastPathComponent))
                } else if Self.editableExtensions.contains(url.pathExtension.lowercased()) {
                    files.append(SidebarNode(kind: .file(url),
                                             displayName: url.deletingPathExtension().lastPathComponent))
                }
            }
        }
        folders.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        files.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return folders + files
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? SidebarNode else { return roots.count }
        return node.children?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? SidebarNode {
            return node.children?[index] as Any
        }
        return roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? SidebarNode else { return false }
        return node.isFolder
    }

    // MARK: - Lazy expansion

    /// Kick off the async listing the moment a folder is actually expanded —
    /// the only time its contents are ever scanned.
    func outlineViewItemDidExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? SidebarNode,
              node.isFolder, node.children == nil else { return }
        guard let url = node.url else { return }
        loadChildren(of: node, in: url)
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SidebarNode else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("SidebarCell")
        let cell: NSTableCellView
        if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(image)
            cell.imageView = image
            let field = NSTextField(labelWithString: "")
            field.font = NSFont.systemFont(ofSize: 12)
            field.lineBreakMode = .byTruncatingMiddle
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            cell.textField = field
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                image.heightAnchor.constraint(equalToConstant: 16),
                field.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 4),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        cell.textField?.stringValue = node.displayName
        cell.imageView?.image = node.isFolder
            ? NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            : NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        return cell
    }

    // MARK: - Row click

    @objc private func openClickedRow(_ sender: Any?) {
        let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
        guard row >= 0, let node = outline.item(atRow: row) as? SidebarNode else { return }
        guard case .file(let url) = node.kind else { return }
        onOpenFile?(url)
    }
}
