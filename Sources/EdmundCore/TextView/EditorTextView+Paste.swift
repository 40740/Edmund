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

        // 1. Prefer an image on the board. Screenshots (⌃⌘⇧4) and WeChat/other
        //    clip tools often ALSO write a `.string` — sometimes an empty string
        //    or a promised-file URL — which would otherwise hijack the text
        //    branch below and result in pasting nothing (or a bogus path) while
        //    silently dropping the image. So always try the image path FIRST.
        if pasteImageIfPresent(pasteboard) { return }

        // 2. Otherwise paste as plain text. Ignore an empty string (a clipboard
        //    that only holds an image with a stray empty `.string`).
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            // Replace the current selection through the normal editing pipeline.
            // `super.insertText` (not the auto-pair override) so pasting never
            // auto-closes brackets, and the single bulk edit funnels through
            // didChangeText once.
            super.insertText(text, replacementRange: selectedRange())
            return
        }

        // 3. Fall back to NSTextView's default (rich text / other types).
        super.paste(sender)
    }

    /// If the pasteboard holds an image (e.g. a screenshot / copied graphic),
    /// write it into an `images/` folder beside the current document and insert
    /// `![](./images/name.png)` at the caret. Returns true when handled.
    ///
    /// Fully offline, synchronous, and only on the paste action — no resident
    /// resources, so it never touches the open/秒开 path.
    private func pasteImageIfPresent(_ pasteboard: NSPasteboard) -> Bool {
        // Read the image data explicitly (PNG first, then TIFF) rather than
        // relying solely on `NSImage(pasteboard:)`, which can be flaky for
        // boards that carry only a `public.png` representation (common for
        // macOS ⌃⌘⇧4 screenshots and WeChat clips).
        let rawData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
        guard let data = rawData else { return false }
        guard let image = NSImage(data: data) else { return false }

        guard let dir = document?.fileURL?.deletingLastPathComponent() else {
            // The document hasn't been saved to disk yet, so there's no folder
            // beside it to write the image into. Tell the user to save first so
            // the image isn't silently dropped.
            NSSound.beep()
            if let window = window {
                let alert = NSAlert()
                alert.messageText = "请先保存文档"
                alert.informativeText = "粘贴图片需要先把文档保存到磁盘（图片会存放在文档旁的 images/ 文件夹）。"
                alert.alertStyle = .informational
                alert.beginSheetModal(for: window)
            }
            return false
        }

        // Encode as PNG regardless of the source representation so the saved
        // file is always a portable PNG.
        guard let pngData = encodePNG(from: image, original: data) else { return false }

        let imagesDir = dir.appendingPathComponent("images", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            let name = "paste-\(Int(Date().timeIntervalSince1970)).png"
            let fileURL = imagesDir.appendingPathComponent(name)
            try pngData.write(to: fileURL)
            let reference = "![paste](./images/\(name))"
            super.insertText(reference, replacementRange: selectedRange())
            return true
        } catch {
            Log.error("Could not save pasted image: \(error)", category: .io)
            return false
        }
    }

    /// Encode an image to PNG data, decoding the source bytes (PNG or TIFF)
    /// and re-encoding to a portable PNG via AppKit.
    private func encodePNG(from image: NSImage, original data: Data) -> Data? {
        // Try the source bytes directly first — already a valid PNG most of the
        // time for screenshots, which avoids an extra decode/encode pass.
        if let rep = NSBitmapImageRep(data: data),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        // Fall back to decoding through NSImage (handles TIFF and other forms).
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return png
    }
}
