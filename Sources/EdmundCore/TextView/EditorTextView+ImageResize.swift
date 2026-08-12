import AppKit

// MARK: - Lightweight image drag-to-resize
//
// Hovering over a rendered image (edit mode, cursor outside the token) reveals
// a small resize handle at the image's bottom-right corner. Dragging it scales
// the image's width proportionally; on mouse-up the new dimensions are written
// back to the Markdown source as an `<img src="…" width="N" height="N">` tag
// (the format both Edit and Read/export already render).
//
// Lightweight by construction: the handle is a plain subview, created lazily,
// shown only on hover, and nothing runs while the mouse is away from an image.
// No timers, no listeners, no resident work — fully off the open/秒开 path.

extension EditorTextView {

    // MARK: - State

    /// The lazily-created resize handle (a small drag thumb at the corner of a
    /// hovered image). Kept via associated objects so the extension adds no
    /// stored properties to the NSTextView subclass.
    private var imageResizeHandle: ImageResizeHandleView? {
        get { objc_getAssociatedObject(self, &imageResizeHandleKey) as? ImageResizeHandleView }
        set { objc_setAssociatedObject(self, &imageResizeHandleKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    /// The source range of the image token currently being resized.
    private var resizingImageRange: NSRange? {
        get { (objc_getAssociatedObject(self, &resizingImageRangeKey) as? NSValue)?.rangeValue }
        set { objc_setAssociatedObject(self, &resizingImageRangeKey,
                                       newValue.map { NSValue(range: $0) },
                                       .OBJC_ASSOCIATION_RETAIN) }
    }

    /// The destination (file path) of the image currently being resized, so we
    /// can re-find it on mouse-up after recompose shifts ranges.
    private var resizingImageDest: String? {
        get { objc_getAssociatedObject(self, &resizingImageDestKey) as? String }
        set { objc_setAssociatedObject(self, &resizingImageDestKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    /// The current drag's origin point (in view coordinates) at mouse-down.
    private var resizeDragStart: NSPoint? {
        get { (objc_getAssociatedObject(self, &resizeDragStartKey) as? NSValue)?.pointValue }
        set { objc_setAssociatedObject(self, &resizeDragStartKey,
                                       newValue.map { NSValue(point: $0) },
                                       .OBJC_ASSOCIATION_RETAIN) }
    }

    /// The image's natural size (unscaled), used to keep the aspect ratio
    /// while dragging.
    private var resizeNaturalSize: NSSize? {
        get { (objc_getAssociatedObject(self, &resizeNaturalSizeKey) as? NSValue)?.sizeValue }
        set { objc_setAssociatedObject(self, &resizeNaturalSizeKey,
                                       newValue.map { NSValue(size: $0) },
                                       .OBJC_ASSOCIATION_RETAIN) }
    }

    /// The image's width at drag start, in pixels (natural units).
    private var resizeStartWidth: CGFloat {
        get { (objc_getAssociatedObject(self, &resizeStartWidthKey) as? NSNumber)?.doubleValue ?? 0 }
        set { objc_setAssociatedObject(self, &resizeStartWidthKey, NSNumber(value: Double(newValue)),
                                       .OBJC_ASSOCIATION_RETAIN) }
    }

    /// The image's rendered rect (view coords) at drag start, used to track
    /// the handle as the drag moves (the source isn't rewritten until mouse-up).
    private var resizeStartRect: CGRect? {
        get { (objc_getAssociatedObject(self, &resizeStartRectKey) as? NSValue)?.rectValue }
        set { objc_setAssociatedObject(self, &resizeStartRectKey,
                                       newValue.map { NSValue(rect: $0) },
                                       .OBJC_ASSOCIATION_RETAIN) }
    }

    // MARK: - Tracking

    /// Install a mouse-moved tracking area so hover can reveal the handle.
    /// Idempotent; the code-copy tracking is installed independently.
    func installImageResizeTracking() {
        if trackingAreas.contains(where: { $0.owner === self
                && $0.userInfo?[imageResizeTrackingKey] as? Bool == true }) {
            return
        }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .activeInKeyWindow,
                                            .inVisibleRect],
                                  owner: self, userInfo: [imageResizeTrackingKey: true])
        addTrackingArea(area)
    }

    /// Updates the resize handle's visibility/position for the given point in
    /// text-view coordinates. Shows the handle when the mouse is over a
    /// rendered image (but not while actively resizing another one).
    func updateImageResizeHandle(for point: NSPoint) {
        guard !isResizingImage else { return }

        if let (offset, overlay) = imageOverlay(at: point) {
            guard let rect = renderedRect(forOverlayAt: offset, overlay: overlay) else {
                hideImageResizeHandle()
                return
            }
            showImageResizeHandle(at: rect, imageRange: imageRangeContaining(offset),
                                  destination: imageDestination(for: offset))
        } else {
            hideImageResizeHandle()
        }
    }

    /// The first image overlay whose rendered rect contains `point` (view
    /// coords), or nil. Returns the document-level character offset of the
    /// image's anchor (`!` of `![…]`, `<` of `<img …>`, or `!` of `![[…]]`).
    private func imageOverlay(at point: NSPoint) -> (offset: Int, overlay: FragmentOverlay)? {
        guard let tlm = textLayoutManager else { return nil }
        let origin = textContainerOrigin

        // Enumerate all visible layout fragments and check each overlay's rect.
        // `enumerateTextLayoutFragments` is cheap and covers only laid-out
        // (visible) regions.
        var result: (Int, FragmentOverlay)?
        tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location,
                                         options: [.ensuresLayout]) { fragment in
            guard let decorated = fragment as? DecoratedTextLayoutFragment else { return true }
            guard let paraStart = fragment.textElement?.elementRange?.location else { return true }
            let paraStartDoc = tlm.offset(from: tlm.documentRange.location, to: paraStart)
            for (paraOffset, overlay) in decorated.overlays {
                guard overlay.image != nil else { continue }  // only real images get a handle
                guard let rect = decorated.overlayRect(anchorOffset: paraOffset, overlay: overlay)
                else { continue }
                // Fragment-local rect → container coords.
                let frame = fragment.layoutFragmentFrame
                let containerRect = CGRect(x: frame.minX + rect.minX,
                                           y: frame.minY + rect.minY,
                                           width: rect.width, height: rect.height)
                // Container coords → view coords.
                let viewRect = containerRect.offsetBy(dx: origin.x, dy: origin.y)
                if viewRect.insetBy(dx: -4, dy: -4).contains(point) {
                    result = (paraStartDoc + paraOffset, overlay)
                    return false
                }
            }
            return true
        }
        return result
    }

    /// The rendered rect (view coordinates) for the image overlay anchored at
    /// the document-level character `offset`.
    private func renderedRect(forOverlayAt offset: Int, overlay: FragmentOverlay) -> CGRect? {
        guard let tlm = textLayoutManager,
              let loc = tlm.location(tlm.documentRange.location, offsetBy: offset) else { return nil }
        tlm.ensureLayout(for: NSTextRange(location: loc))
        guard let fragment = tlm.textLayoutFragment(for: loc) else { return nil }
        guard let decorated = fragment as? DecoratedTextLayoutFragment else { return nil }

        // Convert the document offset to a paragraph-relative offset.
        guard let paraStart = fragment.textElement?.elementRange?.location else { return nil }
        let offsetInPara = tlm.offset(from: paraStart, to: loc)
        guard let rect = decorated.overlayRect(anchorOffset: offsetInPara, overlay: overlay)
        else { return nil }

        let frame = fragment.layoutFragmentFrame
        let origin = textContainerOrigin
        return CGRect(x: frame.minX + rect.minX + origin.x,
                      y: frame.minY + rect.minY + origin.y,
                      width: rect.width, height: rect.height)
    }

    // MARK: - Handle management

    private func showImageResizeHandle(at rect: CGRect, imageRange: NSRange?, destination: String?) {
        let handle = imageResizeHandle ?? makeImageResizeHandle()
        handle.frame = CGRect(x: rect.maxX - 8, y: rect.maxY - 8, width: 16, height: 16)
        handle.isHidden = false
        resizingImageRange = imageRange
        resizingImageDest = destination
    }

    func hideImageResizeHandle() {
        imageResizeHandle?.isHidden = true
        if !isResizingImage {
            resizingImageRange = nil
            resizingImageDest = nil
        }
    }

    private func makeImageResizeHandle() -> ImageResizeHandleView {
        let handle = ImageResizeHandleView()
        handle.isHidden = true
        handle.editor = self
        addSubview(handle)
        imageResizeHandle = handle
        return handle
    }

    /// Whether an image-resize drag is in progress (guards the handle and
    /// mouse-up writer).
    private var isResizingImage: Bool {
        resizeDragStart != nil
    }

    // MARK: - Drag handling

    /// Begins a resize drag from the handle at the given view-coordinate point.
    func beginImageResize(at point: NSPoint) {
        guard let handle = imageResizeHandle, !handle.isHidden,
              let range = resizingImageRange,
              let dest = resizingImageDest else { return }

        // Capture the current rendered width as the drag baseline and remember
        // the image's natural size so aspect ratio is preserved.
        let naturalSize = imageNaturalSize(destination: dest)
        guard naturalSize.width > 0, naturalSize.height > 0 else { return }
        resizeNaturalSize = naturalSize

        // Remember the image's rendered rect so we can track the handle.
        if let (offset, overlay) = imageOverlay(at: handle.frame.origin) {
            resizeStartRect = renderedRect(forOverlayAt: offset, overlay: overlay)
        }

        // The current rendered width: from the handle's position at the image
        // corner, or compute from the current source.
        let currentWidth = imageCurrentWidth(destination: dest) ?? naturalSize.width
        resizeStartWidth = currentWidth
        resizeDragStart = point
    }

    /// Updates the resize during a drag. `deltaX` is view-pixels from drag
    /// start; it maps to a proportional width in natural units.
    func updateImageResize(to point: NSPoint) {
        guard let start = resizeDragStart,
              let naturalSize = resizeNaturalSize,
              let handle = imageResizeHandle,
              let startRect = resizeStartRect else { return }

        let deltaX = point.x - start.x
        // Map view pixels to natural units using the current scale.
        let viewScale = startRect.width / max(1, resizeStartWidth)
        var newWidth = resizeStartWidth + (deltaX / max(0.1, viewScale))
        newWidth = max(40, min(newWidth, 3000))   // sane clamp

        // Project the new rendered width and move the handle to the new
        // bottom-right corner so the user gets live feedback.
        let scale = newWidth / max(1, resizeStartWidth)
        let projectedWidth = startRect.width * scale
        let projectedHeight = startRect.height * scale
        handle.frame = CGRect(x: startRect.maxX + (projectedWidth - startRect.width) - 8,
                              y: startRect.maxY + (projectedHeight - startRect.height) - 8,
                              width: 16, height: 16)
    }

    /// Ends the drag and writes the new dimensions into the markdown source.
    func endImageResize(at point: NSPoint) {
        defer {
            resizeDragStart = nil
            resizeNaturalSize = nil
            resizeStartWidth = 0
            resizeStartRect = nil
            // Keep the handle visible until the mouse leaves; the next
            // mouseMoved will hide it or reposition it.
            updateImageResizeHandle(for: point)
        }

        guard let start = resizeDragStart,
              let naturalSize = resizeNaturalSize,
              let startRect = resizeStartRect,
              let dest = resizingImageDest else { return }

        let deltaX = point.x - start.x
        let viewScale = startRect.width / max(1, resizeStartWidth)
        var newWidth = resizeStartWidth + (deltaX / max(0.1, viewScale))
        newWidth = max(40, min(newWidth, 3000))
        let newHeight = naturalSize.height * (newWidth / naturalSize.width)

        // Find the image token in the raw source and rewrite it with <img>.
        writeImageSize(to: dest, width: Int(newWidth.rounded()), height: Int(newHeight.rounded()))
    }

    /// Computes the natural (unscaled) pixel size of the image at `destination`.
    private func imageNaturalSize(destination: String) -> NSSize {
        guard let url = resolveImageURL(destination),
              let image = NSImage(contentsOf: url) else { return .zero }
        return image.size
    }

    /// The currently rendered width of the image, parsed from its markdown, or
    /// nil if no explicit dimension is set (natural size then applies).
    func imageCurrentWidth(destination: String) -> CGFloat? {
        guard let range = imageRange(forDestination: destination) else { return nil }
        let ns = rawSource as NSString
        guard range.upperBound <= ns.length else { return nil }
        let token = ns.substring(with: range)

        // <img ... width="N" ...> or ![[file|N]]
        if let widthAttr = imgWidthRegex.firstMatch(in: token, range: NSRange(location: 0, length: (token as NSString).length)),
           let value = parseAttrValue(from: token, match: widthAttr) {
            return CGFloat(value)
        }
        // Obsidian embed syntax ![[file|N]]
        if token.hasPrefix("![[") {
            let nsToken = token as NSString
            let pipeLoc = nsToken.range(of: "|").location
            if pipeLoc != NSNotFound, pipeLoc < nsToken.length - 2 {
                let rest = nsToken.substring(from: pipeLoc + 1)
                let digits = rest.components(separatedBy: CharacterSet.decimalDigits.inverted).first ?? ""
                if let w = Int(digits) {
                    return CGFloat(w)
                }
            }
        }
        return nil
    }

    var imgWidthRegex: NSRegularExpression {
        try! NSRegularExpression(pattern: #"width\s*=\s*[\"']?(\d+)[\"']?"#)
    }

    private func parseAttrValue(from s: String, match: NSTextCheckingResult) -> Int? {
        guard match.numberOfRanges > 1 else { return nil }
        let ns = s as NSString
        let r = match.range(at: 1)
        guard r.location != NSNotFound else { return nil }
        return Int(ns.substring(with: r))
    }

    /// Finds the source range of the image token containing character `offset`.
    private func imageRangeContaining(_ offset: Int) -> NSRange? {
        imageTokenRange(containing: offset)
    }

    /// Directly scans `rawSource` for `![...](...)`, `<img ...>`, `![[...]]`
    /// tokens and returns the one containing `offset`.
    func imageTokenRange(containing offset: Int) -> NSRange? {
        let ns = rawSource as NSString
        let whole = NSRange(location: 0, length: ns.length)

        let patterns = [
            #"!\[[^\]]*\]\([^)]*\)"#,       // ![alt](path)
            #"<img[^>]*>"#,                  // <img ...>
            #"!\[\[[^\]]*\]\]"#,             // ![[file|N]]
        ]
        for pattern in patterns {
            let regex = try? NSRegularExpression(pattern: pattern)
            guard let regex else { continue }
            for m in regex.matches(in: rawSource, range: whole) {
                if NSLocationInRange(offset, m.range) {
                    return m.range
                }
            }
        }
        return nil
    }

    /// The destination path of the image token containing `offset`.
    func imageDestination(for offset: Int) -> String? {
        guard let range = imageTokenRange(containing: offset) else { return nil }
        let ns = rawSource as NSString
        let token = ns.substring(with: range)

        // ![alt](path)
        if let m = try? NSRegularExpression(pattern: #"\]\(([^)]+)\)"#)
            .firstMatch(in: token, range: NSRange(location: 0, length: (token as NSString).length)) {
            if m.numberOfRanges > 1 {
                let p = m.range(at: 1)
                if p.location != NSNotFound {
                    return (token as NSString).substring(with: p)
                }
            }
        }
        // <img src="path">
        if let m = try? NSRegularExpression(pattern: #"src\s*=\s*[\"']([^\"']+)[\"']"#)
            .firstMatch(in: token, range: NSRange(location: 0, length: (token as NSString).length)) {
            if m.numberOfRanges > 1 {
                let p = m.range(at: 1)
                if p.location != NSNotFound {
                    return (token as NSString).substring(with: p)
                }
            }
        }
        // ![[file|N]] — strip the |size suffix
        if token.hasPrefix("![["), token.hasSuffix("]]") {
            let inner = String(token.dropFirst(3).dropLast(2))
            return inner.components(separatedBy: "|").first
        }
        return nil
    }

    /// Finds the source range of the image token for `destination`.
    func imageRange(forDestination dest: String) -> NSRange? {
        let ns = rawSource as NSString
        let whole = NSRange(location: 0, length: ns.length)
        let patterns = [
            #"!\[[^\]]*\]\([^)]*\)"#,
            #"<img[^>]*>"#,
            #"!\[\[[^\]]*\]\]"#,
        ]
        for pattern in patterns {
            let regex = try? NSRegularExpression(pattern: pattern)
            guard let regex else { continue }
            for m in regex.matches(in: rawSource, range: whole) {
                let token = ns.substring(with: m.range)
                if let tokenDest = imageDestinationFromToken(token), tokenDest == dest {
                    return m.range
                }
            }
        }
        return nil
    }

    func imageDestinationFromToken(_ token: String) -> String? {
        let ns = token as NSString
        // ![alt](path)
        if let m = try? NSRegularExpression(pattern: #"\]\(([^)]+)\)"#)
            .firstMatch(in: token, range: NSRange(location: 0, length: ns.length)) {
            if m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound {
                return ns.substring(with: m.range(at: 1))
            }
        }
        // <img src="path">
        if let m = try? NSRegularExpression(pattern: #"src\s*=\s*[\"']([^\"']+)[\"']"#)
            .firstMatch(in: token, range: NSRange(location: 0, length: ns.length)) {
            if m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound {
                return ns.substring(with: m.range(at: 1))
            }
        }
        // ![[file|N]]
        if token.hasPrefix("![["), token.hasSuffix("]]") {
            let inner = String(token.dropFirst(3).dropLast(2))
            return inner.components(separatedBy: "|").first
        }
        return nil
    }

    /// Rewrites the image token for `destination` in `rawSource` as an
    /// `<img src="…" width="N" height="N">` tag. The replacement goes through
    /// the editor's own edit pipeline (undoable, block-restyled) so it behaves
    /// exactly like a formatting command.
    private func writeImageSize(to destination: String, width: Int, height: Int) {
        guard let range = imageRange(forDestination: destination) else { return }
        let ns = rawSource as NSString
        guard range.upperBound <= ns.length else { return }
        let newToken = "<img src=\"\(destination)\" width=\"\(width)\" height=\"\(height)\">"
        applyFormattingEdit(rawRange: range, replacement: newToken,
                            select: NSRange(location: range.location, length: 0))
    }
}

// MARK: - Resize handle view

/// A small 16×16 drag thumb shown at the bottom-right corner of a hovered
/// image. Uses the standard macOS resize glyph; a `mouseDown`/`mouseDragged`/
/// `mouseUp` loop drives the resize on the owning editor.
final class ImageResizeHandleView: NSView {
    weak var editor: EditorTextView?

    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
        NSColor(calibratedWhite: 0.1, alpha: 0.85).setFill()
        circle.fill()
        // Diagonal grip lines.
        let grip = NSBezierPath()
        for i in 0..<3 {
            let inset = 3 + CGFloat(i) * 3
            grip.move(to: NSPoint(x: bounds.maxX - CGFloat(inset) - 1, y: bounds.minY + CGFloat(inset)))
            grip.line(to: NSPoint(x: bounds.maxX - CGFloat(inset) - 4, y: bounds.minY + CGFloat(inset) + 3))
        }
        NSColor.white.setStroke()
        grip.lineWidth = 1.2
        grip.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let viewPoint = editor?.convert(event.locationInWindow, from: nil) ?? point
        editor?.beginImageResize(at: viewPoint)
    }

    override func mouseDragged(with event: NSEvent) {
        let viewPoint = editor?.convert(event.locationInWindow, from: nil) ?? .zero
        editor?.updateImageResize(to: viewPoint)
    }

    override func mouseUp(with event: NSEvent) {
        let viewPoint = editor?.convert(event.locationInWindow, from: nil) ?? .zero
        editor?.endImageResize(at: viewPoint)
    }
}

// MARK: - Associated-object keys

/// Associated-object keys. `nonisolated(unsafe)`: these are only touched from
/// the main actor (they're backing stored properties of this main-actor view),
/// so the marker is safe — matching the existing code-copy-button keys.
private nonisolated(unsafe) var imageResizeHandleKey: UInt8 = 0
private nonisolated(unsafe) var resizingImageRangeKey: UInt8 = 0
private nonisolated(unsafe) var resizingImageDestKey: UInt8 = 0
private nonisolated(unsafe) var resizeDragStartKey: UInt8 = 0
private nonisolated(unsafe) var resizeNaturalSizeKey: UInt8 = 0
private nonisolated(unsafe) var resizeStartWidthKey: UInt8 = 0
private nonisolated(unsafe) var resizeStartRectKey: UInt8 = 0
private nonisolated(unsafe) let imageResizeTrackingKey = "imageResizeTracking"
