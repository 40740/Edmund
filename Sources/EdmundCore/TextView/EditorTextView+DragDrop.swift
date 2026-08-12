import AppKit
import UniformTypeIdentifiers

/// Reads the list of file URLs carried by an NSPasteboard, if any.
private extension NSPasteboard {
    func fileURLs() -> [URL] {
        // Modern API: `readObjects` vends NSURL for the fileURL type.
        if let objects = readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            let urls = objects.compactMap { $0 as? URL }
            if !urls.isEmpty { return urls }
        }
        // Legacy fallback: the `NSFilenamesPboardType` array of path strings.
        if let paths = propertyList(forType: .init("NSFilenamesPboardType")) as? [String] {
            return paths.map { URL(fileURLWithPath: $0) }
        }
        // Another legacy fallback: a single file URL string.
        if let s = string(forType: .fileURL) {
            return [URL(fileURLWithPath: s.replacingOccurrences(of: "file://", with: ""))]
        }
        return []
    }
}

// MARK: - Drag & drop image / file insertion
//
// The editor previously did not register for dragged types at all — dropping a
// screenshot or a file onto the window did nothing. This adds a lightweight
// drag destination that, on drop, inserts the appropriate Markdown reference at
// the caret:
//   - image file  -> `![](relativePath)`  (path computed relative to the document)
//   - .md/.markdown file -> `[name](path)` link
//   - any other file -> `[name](path)` link
//
// Everything happens once, synchronously, at the moment of the drop. No
// timers, no listeners, no resident resources — fully off the open/秒开 path.

extension EditorTextView {

    /// The set of image file extensions the app treats as "drop → image
    /// reference". Mirrors the renderer's image set so the reference will
    /// actually be rendered in Read mode.
    private static nonisolated let dropImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "heif", "bmp", "tiff",
    ]

    /// Register the editor as a drag destination. Called from
    /// `viewDidMoveToWindow` once the view lands in a window.
    func installDragDropRegistration() {
        registerForDraggedTypes([.fileURL, .string])
    }

    /// Accept drops that carry file URLs (or a plain string for convenience).
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard validateDrop(sender) else { return [] }
        return .copy
    }

    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard validateDrop(sender) else { return [] }
        return .copy
    }

    private func validateDrop(_ sender: NSDraggingInfo) -> Bool {
        let types = sender.draggingPasteboard.types ?? []
        return types.contains(.fileURL)
            || types.contains(.string)
            || types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType"))
    }

    /// On drop, read the file URLs (or a pasted string) and insert references.
    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard

        // Prefer real file URLs (image / md / other files).
        let urls = pasteboard.fileURLs()
        if !urls.isEmpty {
            var pieces: [String] = []
            for url in urls {
                pieces.append(reference(for: url))
            }
            insertMarkdown(pieces.joined(separator: "\n"))
            return true
        }

        // Fall back to a plain string drop (insert the text as-is).
        if let text = pasteboard.string(forType: .string) {
            insertMarkdown(text)
            return true
        }
        return false
    }

    /// Build the Markdown reference for a dropped file.
    private func reference(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        let name = url.deletingPathExtension().lastPathComponent
        let path = relativePath(for: url)

        if Self.dropImageExtensions.contains(ext) {
            return "![\(name)](\(path))"
        }
        if ext == "md" || ext == "markdown" {
            return "[\(url.lastPathComponent)](\(path))"
        }
        return "[\(url.lastPathComponent)](\(path))"
    }

    /// Compute the path of `fileURL` relative to the current document's
    /// directory, falling back to the absolute path when there is no document.
    private func relativePath(for url: URL) -> String {
        guard let docDir = document?.fileURL?.deletingLastPathComponent() else {
            return url.absoluteString
        }
        return Self.relativePath(from: url, toDirectory: docDir)
    }

    /// Pure path helper (testable, nonisolated): the path of `fileURL` relative
    /// to `directory`, or the absolute path when they don't share a prefix.
    static nonisolated func relativePath(from fileURL: URL, toDirectory directory: URL) -> String {
        let docPath = directory.standardizedFileURL.path
        let targetPath = fileURL.standardizedFileURL.path
        guard docPath.hasPrefix("/"), targetPath.hasPrefix(docPath) else {
            return fileURL.path
        }
        let relative = String(targetPath.dropFirst(docPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? fileURL.path : relative
    }

    /// Insert `text` at the caret through the normal editing pipeline (same
    /// path as paste) so it is recorded for undo and re-rendered once.
    private func insertMarkdown(_ text: String) {
        guard !text.isEmpty else { return }
        super.insertText(text, replacementRange: selectedRange())
    }
}
