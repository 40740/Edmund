import AppKit

// MARK: - Plain-text paste
//
// NSTextView's default `paste` reads the RICHEST format on the pasteboard and
// converts it to an attributed string. When text was copied from another app —
// a browser, Pages, a web page, a PDF — that conversion walks the pasteboard's
// HTML / RTF / RTFD (often many style runs) and can take many seconds for a
// sizable chunk. That is the "loading 十几秒 / 很卡" felt when pasting external
// text into Edmund.
//
// This editor is a Markdown editor: it recomposes and restyles everything
// itself on every edit (attribute-only, via `recomposeDirty`), so any rich
// attributes the default paste produced are thrown away the instant the edit is
// re-rendered. Converting the pasteboard's rich formats is pure wasted work.
//
// We therefore paste as PLAIN TEXT: read only the `.string` representation and
// insert it directly through the normal edit pipeline (shouldChangeText → undo
// record → didChangeText → incremental parse → restyle). Same result, no costly
// rich-text conversion, no paste lag. Fully offline — no impact on the open /
// save path.

extension EditorTextView {

    /// Paste as plain text. Falls back to the standard rich-text path only when
    /// the pasteboard has no plain-text representation (e.g. an image or a
    /// format that has no `.string` form), so the user is never stuck.
    public override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string) else {
            // No plain text on the board. If it carries an actual image, save it
            // next to the document and insert a Markdown image reference instead
            // of falling through to NSTextView's rich-text paste (which would
            // drop the image with no on-disk copy and no `![](…)` reference).
            if pasteImageIfPresent(pasteboard) { return }
            super.paste(sender)
            return
        }
        // Replace the current selection with the pasted text through the normal
        // editing pipeline. `super.insertText` (not the auto-pair override) so
        // pasting never auto-closes brackets, and the single bulk edit funnels
        // through didChangeText once.
        super.insertText(text, replacementRange: selectedRange())
    }

    /// If the pasteboard holds an image (e.g. a screenshot / copied graphic),
    /// write it into an `images/` folder beside the current document and insert
    /// `![](./images/name.png)` at the caret. Returns true when handled.
    ///
    /// Fully offline, synchronous, and only on the paste action — no resident
    /// resources, so it never touches the open/秒开 path.
    private func pasteImageIfPresent(_ pasteboard: NSPasteboard) -> Bool {
        guard let image = NSImage(pasteboard: pasteboard) else { return false }
        guard let dir = document?.fileURL?.deletingLastPathComponent() else {
            // No on-disk document yet: nothing sensible to save beside. Let the
            // caller fall through to the default paste (or do nothing).
            return false
        }
        guard let png = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: png),
              let data = rep.representation(using: .png, properties: [:]) else {
            return false
        }

        let imagesDir = dir.appendingPathComponent("images", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            let name = "paste-\(Int(Date().timeIntervalSince1970)).png"
            let fileURL = imagesDir.appendingPathComponent(name)
            try data.write(to: fileURL)
            let reference = "![paste](./images/\(name))"
            super.insertText(reference, replacementRange: selectedRange())
            return true
        } catch {
            Log.error("Could not save pasted image: \(error)", category: .io)
            return false
        }
    }
}
