import AppKit

// MARK: - Edit-mode code-block copy button
//
// A small "复制" pill floats at the top-right of the fenced code block under
// the mouse (ColaMD's behavior), copying the block's code without the fence
// lines. The button is a subview of the text view, so it scrolls with the
// document; a tracking area feeds `mouseMoved` to reposition/show/hide it.

extension EditorTextView {

    /// The copy button, lazily created on first hover.
    private var codeCopyButton: NSButton {
        if let existing = objc_getAssociatedObject(self, &codeCopyButtonKey) as? NSButton {
            return existing
        }
        let button = NSButton(title: "复制", target: self,
                              action: #selector(codeCopyButtonClicked(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: 11)
        button.isHidden = true
        button.setButtonType(.momentaryPushIn)
        // The code block's panel is dark in Elegant — the pill must stand out
        // against it, so pin a light chip with dark ink instead of letting the
        // system pick a dark button that vanishes into the panel.
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.backgroundColor = NSColor(calibratedWhite: 0.97, alpha: 1).cgColor
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NSColor(calibratedWhite: 0.65, alpha: 0.5).cgColor
        button.contentTintColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        addSubview(button)
        objc_setAssociatedObject(self, &codeCopyButtonKey, button, .OBJC_ASSOCIATION_RETAIN)
        return button
    }

    /// Whether the mouse is currently over a fenced code block (drives the
    /// hover button), tracked in document coordinates so scrolling keeps it
    /// accurate.
    private var hoveredCodeBlockRange: NSRange? {
        get { (objc_getAssociatedObject(self, &hoveredRangeKey) as? NSValue)?.rangeValue }
        set { objc_setAssociatedObject(self, &hoveredRangeKey,
                                       newValue.map { NSValue(range: $0) },
                                       .OBJC_ASSOCIATION_RETAIN) }
    }

    /// Install a mouse-moved tracking area so hover can reveal the button.
    func installCodeCopyTracking() {
        if trackingAreas.contains(where: { $0.owner === self
                && $0.userInfo?[codeCopyTrackingKey] as? Bool == true }) {
            return
        }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .mouseEnteredAndExited,
                                            .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: [codeCopyTrackingKey: true])
        addTrackingArea(area)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        installCodeCopyTracking()
        installImageResizeTracking()
    }

    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        updateCodeCopyButton(for: point)
        updateImageResizeHandle(for: point)
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hideCodeCopyButton()
        hideImageResizeHandle()
    }

    /// Repositions the hover button for the point (in text-view coordinates).
    /// The button tracks the code block's bounding box, glued to its top-right.
    func updateCodeCopyButton(for point: NSPoint) {
        guard let block = fencedCodeBlock(at: point) else {
            hideCodeCopyButton()
            return
        }
        guard let rect = renderedRect(forBlock: block) else {
            hideCodeCopyButton()
            return
        }
        let button = codeCopyButton
        button.title = "复制"
        button.sizeToFit()
        let origin = textContainerOrigin
        // Pin the pill to the block's TOP-RIGHT corner (ColaMD behavior).
        // `rect` is in text-container coordinates, which are flipped (y grows
        // downward) — so `minY` is the visual top and `maxX` the right edge.
        // View coords = container coords + container origin. Keep a little
        // inset from the edges so the pill sits neatly inside the panel.
        let x = rect.maxX + origin.x - button.frame.width - 10
        let y = rect.minY + origin.y + 6
        // If the code block is narrower than the pill, don't clamp it to the
        // left edge (that's what made it read as top-LEFT); instead let it
        // keep its right-anchored position so it stays visually top-right.
        button.frame.origin = NSPoint(x: max(rect.minX + origin.x + 4, x), y: y)
        button.isHidden = false
        hoveredCodeBlockRange = block.range
    }

    private func hideCodeCopyButton() {
        codeCopyButton.isHidden = true
        hoveredCodeBlockRange = nil
    }

    /// The fenced code block whose bounding box contains `point` (text-view
    /// coords), or nil. Only near-screen blocks are measured — a cheap first
    /// line-distance check skips far-away blocks without forcing layout.
    private func fencedCodeBlock(at point: NSPoint) -> Block? {
        let origin = textContainerOrigin
        // Everything below is compared in container coordinates.
        let containerPoint = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        var best: Block?
        for block in blocks where block.kind == .fence && block.range.length > 0 {
            guard let first = lineRect(forCharacterAt: block.range.location) else { continue }
            guard abs(first.minY - containerPoint.y) < 4000 else { continue }
            guard let rect = renderedRect(forBlock: block) else { continue }
            if rect.contains(containerPoint) {
                best = block
            }
        }
        return best
    }

    /// The block's bounding box in container coordinates: first line's top to
    /// the last line's bottom.
    ///
    /// The opening/closing fence lines' typographic bounds are narrow (they
    /// only hug the invisible ` ``` ` markers), so using them directly would
    /// shrink the rect to the left edge of the panel and drop the copy button
    /// near the block's top-LEFT. The code panel itself spans the full text
    /// container (the paragraph style indents text inside it), so compute the
    /// rect from the container width.
    private func renderedRect(forBlock block: Block) -> CGRect? {
        guard let first = lineRect(forCharacterAt: block.range.location),
              block.range.upperBound > block.range.location else { return nil }
        let last = lineRect(forCharacterAt: block.range.upperBound - 1) ?? first
        // The panel fills the full container width edge-to-edge (indent is
        // applied *inside* the panel via the paragraph style), so the rect's
        // horizontal extent is the container's, not the fence glyphs'.
        let containerWidth = textContainer?.size.width
            ?? max(first.maxX, last.maxX)
        let x: CGFloat = 0  // container left edge in container coordinates
        return CGRect(x: x, y: first.minY,
                      width: containerWidth, height: last.maxY - first.minY)
    }

    /// The code text of a fence block, fences stripped (ColaMD copies the
    /// plain code only).
    func codeText(forFenceBlock block: Block) -> String? {
        guard block.kind == .fence, block.range.length > 0 else { return nil }
        let ns = rawSource as NSString
        guard block.range.upperBound <= ns.length else { return nil }
        var lines = ns.substring(with: block.range)
            .components(separatedBy: "\n")
        guard lines.count >= 2 else { return nil }
        lines.removeFirst()   // opening ```lang fence
        if let last = lines.last, last.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            lines.removeLast()   // closing ``` fence
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    @objc private func codeCopyButtonClicked(_ sender: Any?) {
        guard let range = hoveredCodeBlockRange,
              let block = blocks.first(where: { $0.range == range }),
              let code = codeText(forFenceBlock: block) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)

        let button = codeCopyButton
        let original = button.title
        button.title = "已复制 ✓"
        button.sizeToFit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            if self.codeCopyButton.title == "已复制 ✓" {
                self.codeCopyButton.title = original
                self.codeCopyButton.sizeToFit()
            }
        }
    }
}

/// Associated-object keys. `nonisolated(unsafe)`: these are only touched from
/// the main actor (the text view's own methods), and associated-object keys
/// need a stable address, so the strict-concurrency global rule is relaxed.
private nonisolated(unsafe) var codeCopyButtonKey: UInt8 = 0
private nonisolated(unsafe) var hoveredRangeKey: UInt8 = 0
private let codeCopyTrackingKey = "code-copy-tracking"
