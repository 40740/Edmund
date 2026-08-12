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

        // 2. If the pasteboard genuinely carries an image but we couldn't turn
        //    it into a markdown reference (e.g. the document isn't saved yet or
        //    the write failed), do NOT fall through to `super.paste` — that
        //    inserts the image as an NSTextAttachment, which this Markdown
        //    editor renders as an invisible/blank placeholder. We already
        //    alerted the user in `pasteImageIfPresent`; make sure we don't also
        //    insert a phantom blank on top.
        if pasteboardContainsImage(pasteboard) { return }

        // 3. Otherwise paste as plain text. Ignore an empty string (a clipboard
        //    that only holds an image with a stray empty `.string`).
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            // Replace the current selection through the normal editing pipeline.
            // `super.insertText` (not the auto-pair override) so pasting never
            // auto-closes brackets, and the single bulk edit funnels through
            // didChangeText once.
            super.insertText(text, replacementRange: selectedRange())
            return
        }

        // 4. Fall back to NSTextView's default (rich text / other types).
        super.paste(sender)
    }

    /// Whether the pasteboard holds image data of any of the common types,
    /// including a plain file URL that points to an image file. Used both to
    /// prefer the image path and to avoid falling through to a blank-text
    /// default paste when the image branch couldn't complete.
    private func pasteboardContainsImage(_ pasteboard: NSPasteboard) -> Bool {
        // Direct image data (PNG/TIFF/JPEG/…).
        let imageDataTypes: [NSPasteboard.PasteboardType] = [
            .png, .tiff,
            .init("public.jpeg"),
            .init("public.image"),
            .init("NSImage"),
        ]
        for type in imageDataTypes where pasteboard.data(forType: type) != nil {
            return true
        }
        // A file URL that resolves to an image file.
        if let fileURL = pasteboard.string(forType: .fileURL),
           let url = URL(string: fileURL) {
            let ext = url.pathExtension.lowercased()
            let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "svg",
                                          "webp", "bmp", "tiff", "tif", "heic", "heif"]
            if imageExts.contains(ext) { return true }
        }
        // Last resort: let AppKit decide whether the board holds an image. Some
        // clip tools (WeChat, several screenshot utilities) register the picture
        // under a private UTI that `data(forType:)` for the well-known types
        // above won't return, but `NSImage(pasteboard:)` still decodes.
        if NSImage(pasteboard: pasteboard) != nil { return true }
        return false
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
        let rawData = pasteboard.data(forType: .png)
            ?? pasteboard.data(forType: .tiff)
            ?? pasteboard.data(forType: .init("public.jpeg"))
            ?? pasteboard.data(forType: .init("public.image"))
            // WeChat / several clip tools register the picture under a private
            // UTI, so the well-known types above return nothing. Sweep every
            // type on the board for raw bytes that still decode to an image.
            ?? firstImageDataFromAnyType(pasteboard)
        guard let data = rawData else {
            // Might still be a file URL pointing at an image (e.g. a copied
            // image file in Finder). Resolve it so we can load the picture.
            if let fileURL = pasteboard.string(forType: .fileURL),
               let url = URL(string: fileURL),
               let fileData = try? Data(contentsOf: url) {
                let img = NSImage(data: fileData)
                if img != nil || looksLikeSupportedImage(fileData) {
                    return pasteImageData(fileData, image: img, nameHint: url.deletingPathExtension().lastPathComponent)
                }
            }
            // Last resort: `NSImage(pasteboard:)` decodes images some tools put
            // on the board under a private UTI (WeChat screenshots etc.). Re-encode
            // whatever AppKit can read into a PNG so we can still save + insert it.
            // Use a robust extractor that walks the image's own representations
            // instead of assuming `tiffRepresentation` is available.
            if let image = NSImage(pasteboard: pasteboard),
               let png = imagePNGData(image) {
                return pasteImageData(png, image: image, nameHint: "paste")
            }
            return false
        }
        let image = NSImage(data: data)
        // Even if AppKit can't decode the image into an NSImage, the bytes may
        // still be a valid PNG/JPEG we can save verbatim — never drop the paste
        // to a blank just because decoding failed.
        if image == nil && !looksLikeSupportedImage(data) {
            return false
        }
        return pasteImageData(data, image: image, nameHint: "paste")
    }

    /// Shared tail of the image-paste path: locate the document folder, write
    /// the image as a PNG, insert the `![](...)` reference, and (crucially)
    /// never fall through to a default paste that would render a blank.
    private func pasteImageData(_ data: Data, image: NSImage?, nameHint: String) -> Bool {
        guard let doc = document else {
            // No owning document at all — there's nothing to write beside.
            NSSound.beep()
            if let window = window {
                let alert = NSAlert()
                alert.messageText = "无法粘贴图片"
                alert.informativeText = "没有可写入的文档。请先新建或打开一个文档，再粘贴图片。"
                alert.alertStyle = .warning
                alert.beginSheetModal(for: window)
            }
            return true
        }
        guard let dir = doc.fileURL?.deletingLastPathComponent() else {
            // The document exists but isn't on disk yet, so there's no folder
            // beside it to write the image into. Instead of making the user do
            // a manual save-then-paste dance, auto-save the document now (this
            // presents the standard Save panel for a brand-new file), then retry
            // the paste once the save completes. Returning `true` (handled) also
            // stops the caller from falling through to a blank default paste.
            pendingImagePaste = PendingImagePaste(data: data, image: image, nameHint: nameHint)
            NotificationCenter.default.addObserver(
                self, selector: #selector(documentDidSave(_:)),
                name: NSDocument.didSaveNotification, object: doc)
            doc.save(self)
            return true
        }

        // Encode as PNG regardless of the source representation so the saved
        // file is always a portable PNG. If PNG encoding fails but the bytes are
        // already a valid image, save them verbatim with their own extension so
        // the paste never silently drops to a blank.
        var useJpegExtension = false
        let pngData: Data?
        if let encoded = encodePNG(from: image, original: data) {
            pngData = encoded
        } else if looksLikeSupportedImage(data) {
            // Saving the raw bytes verbatim; keep the matching extension.
            pngData = data
            useJpegExtension = !looksLikePNG(data)
        } else {
            pngData = nil
        }
        guard let pngData else {
            // We have image bytes but could not produce anything savable.
            // Never fall through to a blank default paste — tell the user.
            NSSound.beep()
            if let window = window {
                let alert = NSAlert()
                alert.messageText = "无法粘贴图片"
                alert.informativeText = "剪贴板里的图片无法被识别/编码为可保存的文件。请重新截图后重试。"
                alert.alertStyle = .warning
                alert.beginSheetModal(for: window)
            }
            return true
        }

        let imagesDir = dir.appendingPathComponent("images", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            let ext = useJpegExtension ? "jpg" : "png"
            let name = "\(sanitizedPrefix(nameHint))-\(Int(Date().timeIntervalSince1970)).\(ext)"
            let fileURL = imagesDir.appendingPathComponent(name)
            try pngData.write(to: fileURL)
            let reference = "![\(nameHint)](./images/\(name))"
            super.insertText(reference, replacementRange: selectedRange())
            return true
        } catch {
            Log.error("Could not save pasted image: \(error)", category: .io)
            NSSound.beep()
            if let window = window {
                let alert = NSAlert()
                alert.messageText = "无法保存图片"
                alert.informativeText = "图片写入失败：\(error.localizedDescription)\n\n请检查文档所在目录的写入权限后重试。"
                alert.alertStyle = .warning
                alert.beginSheetModal(for: window)
            }
            return true
        }
    }

    /// Keeps a file-name hint filesystem-safe (lowercased alnum + hyphen) so a
    /// copied file like “My Screenshot.png” doesn't produce an invalid path.
    private func sanitizedPrefix(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        var out = String(cleaned).lowercased()
        if out.isEmpty { out = "image" }
        return out
    }

    /// Whether `data` starts with the PNG signature.
    private func looksLikePNG(_ data: Data) -> Bool {
        data.starts(with: [0x89, 0x50, 0x4E, 0x47] as [UInt8])
    }

    /// Whether `data` looks like a supported image we can save verbatim when
    /// AppKit's PNG re-encode unexpectedly fails (PNG / JPEG).
    private func looksLikeSupportedImage(_ data: Data) -> Bool {
        looksLikePNG(data)
            || data.starts(with: [0xFF, 0xD8, 0xFF] as [UInt8])   // JPEG
    }

    /// Sweeps every pasteboard type for raw bytes that still decode to an
    /// image. WeChat and several screenshot utilities place the picture under a
    /// private UTI that `data(forType:)` for the well-known types won't return,
    /// but the bytes themselves are usually a valid PNG/JPEG once we ask for
    /// that private type's data directly. Returns the first decodable payload.
    private func firstImageDataFromAnyType(_ pasteboard: NSPasteboard) -> Data? {
        guard let types = pasteboard.types else { return nil }
        for type in types {
            guard let data = pasteboard.data(forType: type) else { continue }
            if looksLikeSupportedImage(data) || NSImage(data: data) != nil {
                return data
            }
        }
        return nil
    }

    /// Robustly extracts a savable PNG from an `NSImage`, walking its own
    /// representations instead of assuming `tiffRepresentation` exists (which
    /// can be nil for some private-UTI boards even when `NSImage(pasteboard:)`
    /// successfully decodes them).
    private func imagePNGData(_ image: NSImage) -> Data? {
        // Preferred path: TIFF → bitmap rep → PNG.
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        // Fallback: walk the image's own representations directly.
        for rep in image.representations {
            guard let bitmap = rep as? NSBitmapImageRep,
                  let png = bitmap.representation(using: .png, properties: [:]) else { continue }
            return png
        }
        return nil
    }

    /// Encode an image to PNG data, decoding the source bytes (PNG or TIFF)
    /// and re-encoding to a portable PNG via AppKit. `image` may be nil when
    /// AppKit failed to decode but the raw bytes are still a valid image.
    private func encodePNG(from image: NSImage?, original data: Data) -> Data? {
        // Try the source bytes directly first — already a valid PNG most of the
        // time for screenshots, which avoids an extra decode/encode pass.
        if let rep = NSBitmapImageRep(data: data),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        // Fall back to decoding through NSImage (handles TIFF and other forms).
        guard let tiff = image?.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return png
    }

    // MARK: - Auto-save then retry paste
    //
    // When an image is pasted into a document that isn't on disk yet, we can't
    // know where to write the `images/` folder. Rather than drop the image or
    // make the user do a manual save-then-paste dance, we auto-save the document
    // first (a brand-new file shows the standard Save panel), then re-run the
    // paste once the save has completed.

    /// The paste queued behind an in-flight auto-save.
    struct PendingImagePaste {
        let data: Data
        let image: NSImage?
        let nameHint: String
    }

    /// Called when the owning document finishes saving. If we had queued an
    /// image paste behind an auto-save, retry it now that `fileURL` is set.
    @objc private func documentDidSave(_ note: Notification) {
        guard let doc = document,
              (note.object as? NSDocument) === doc,
              let pending = pendingImagePaste,
              doc.fileURL != nil
        else {
            return
        }
        pendingImagePaste = nil
        NotificationCenter.default.removeObserver(
            self, name: NSDocument.didSaveNotification, object: doc)
        _ = pasteImageData(pending.data, image: pending.image, nameHint: pending.nameHint)
    }
}
