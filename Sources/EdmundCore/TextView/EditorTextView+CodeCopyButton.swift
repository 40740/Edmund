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
    }

    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateCodeCopyButton(for: convert(event.locationInWindow, from: nil))
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hideCodeCopyButton()
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
        // View coords = container coords + container origin. Nudge the pill up
        // and out of the block's top edge; the block's box already carries its
        // own top padding, so +4 keeps it inside the box.
        let x = rect.maxX + origin.x - button.frame.width - 10
        let y = rect.minY + origin.y + 4
        button.frame.origin = NSPoint(x: max(origin.x + 4, x), y: y)
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
    private func renderedRect(forBlock block: Block) -> CGRect? {
        guard let first = lineRect(forCharacterAt: block.range.location),
              block.range.upperBound > block.range.location else { return nil }
        let last = lineRect(forCharacterAt: block.range.upperBound - 1) ?? first
        let x = min(first.minX, last.minX)
        let width = max(first.maxX, last.maxX) - x
        return CGRect(x: x, y: first.minY,
                      width: width, height: last.maxY - first.minY)
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
