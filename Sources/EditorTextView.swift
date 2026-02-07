import AppKit

/// A single NSTextView that renders each paragraph block as either:
///   - **Rich text** (rendered markdown) — for non-active blocks
///   - **Raw markdown** — for the block containing the cursor
///
/// ## Architecture
///
/// `rawSource` is the **sole source of truth** for the document content.
/// The text storage is a **display-only output** rebuilt from rawSource.
///
/// **Edits** are intercepted in `shouldChangeText(in:replacementString:)`,
/// applied to `rawSource`, then the display is recomposed.
///
/// **Cursor movement** (clicks, arrow keys, etc.) is detected via the
/// `NSTextView.didChangeSelectionNotification`.  When the active block
/// changes, we schedule an async recompose so it runs after the current
/// event is fully processed.
class EditorTextView: NSTextView {

    // MARK: - State

    private var rawSource: String = ""
    private var blocks: [Block] = []
    private var activeBlockIndex: Int? = nil
    private var isUpdating = false
    private var displayRanges: [NSRange] = []
    private var pendingRecompose = false

    // MARK: - Colors (white, black, blue)

    private let accentBlue = NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.9, alpha: 1.0)

    // MARK: - Fonts & Style

    private let bodyFont: NSFont = {
        if let ia = NSFont(name: "iA Writer Mono S", size: 16) { return ia }
        return NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
    }()

    private let bodyParagraphStyle: NSParagraphStyle = {
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 6
        ps.paragraphSpacing = 0
        return ps
    }()

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: NSColor.black,
            .paragraphStyle: bodyParagraphStyle,
        ]
    }

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isRichText = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        allowsUndo = true

        backgroundColor = .white
        insertionPointColor = .black
        selectedTextAttributes = [
            .backgroundColor: accentBlue.withAlphaComponent(0.3),
            .foregroundColor: NSColor.black,
        ]
        typingAttributes = baseAttributes

        rawSource = ""
        blocks = BlockParser.parse(rawSource)
        recompose(cursorInRaw: 0)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectionDidChange(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: self
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Intercept User Edits

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard !isUpdating else { return false }

        // nil replacement = "can I edit here?" query (mouse click, etc.)
        // Must return true or NSTextView won't place the cursor.
        guard let replacement = replacementString else { return true }

        let rawRange = displayRangeToRawRange(affectedCharRange)

        let startIdx = rawSource.utf16Index(at: rawRange.location)
        let endIdx = rawSource.utf16Index(at: rawRange.location + rawRange.length)
        rawSource.replaceSubrange(startIdx..<endIdx, with: replacement)

        let newCursorInRaw = rawRange.location + (replacement as NSString).length

        blocks = BlockParser.parse(rawSource, previous: blocks)
        recompose(cursorInRaw: newCursorInRaw)

        return false
    }

    // MARK: - Selection Change Detection
    //
    // Handles ALL cursor movement: clicks, drag selection, arrow keys,
    // Cmd+A, Home/End, etc.  No mouseDown override needed.
    //
    // We defer the recompose to the next run loop turn so it never interferes
    // with the event that caused the selection change.  This is safe because:
    //   - For clicks: NSTextView finishes its full mouseDown tracking loop,
    //     places the cursor, then our async fires.
    //   - For drag: notifications fire during drag, but we coalesce — only
    //     the last one triggers a recompose.
    //   - For arrow keys: the key event finishes, selection is updated, then
    //     our async fires.

    @objc private func selectionDidChange(_ notification: Notification) {
        guard !isUpdating else { return }

        let sel = selectedRange()
        let rawOffset = displayOffsetToRawOffset(sel.location)
        let newActiveIndex = blockIndexForRawOffset(rawOffset)

        if newActiveIndex != activeBlockIndex && !pendingRecompose {
            pendingRecompose = true
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.isUpdating else { return }
                self.pendingRecompose = false

                // Re-read selection — it may have changed since we scheduled.
                let currentSel = self.selectedRange()
                let rawStart = self.displayOffsetToRawOffset(currentSel.location)
                let rawEnd = self.displayOffsetToRawOffset(currentSel.location + currentSel.length)
                let rawSel = NSRange(location: rawStart, length: rawEnd - rawStart)
                self.recompose(cursorInRaw: rawStart, selectionInRaw: rawSel)
            }
        }
    }

    // MARK: - Display Composition

    private func recompose(cursorInRaw: Int, selectionInRaw: NSRange? = nil) {
        isUpdating = true

        activeBlockIndex = blockIndexForRawOffset(cursorInRaw)

        let composed = NSMutableAttributedString()
        displayRanges = []

        for (i, block) in blocks.enumerated() {
            if i > 0 {
                composed.append(NSAttributedString(string: "\n\n", attributes: baseAttributes))
            }

            let blockDisplayStart = composed.length

            if i == activeBlockIndex {
                composed.append(NSAttributedString(string: block.content, attributes: baseAttributes))
            } else {
                composed.append(renderMarkdown(block.content))
            }

            let blockDisplayLength = composed.length - blockDisplayStart
            displayRanges.append(NSRange(location: blockDisplayStart, length: blockDisplayLength))
        }

        let fullRange = NSRange(location: 0, length: textStorage!.length)
        textStorage?.beginEditing()
        textStorage?.replaceCharacters(in: fullRange, with: composed)
        textStorage?.endEditing()

        // Restore selection mapped to the new display layout.
        if let rawSel = selectionInRaw, rawSel.length > 0 {
            let displayStart = rawOffsetToDisplayOffset(rawSel.location)
            let displayEnd = rawOffsetToDisplayOffset(rawSel.location + rawSel.length)
            let len = textStorage!.length
            let displaySel = NSRange(
                location: min(displayStart, len),
                length: max(0, min(displayEnd, len) - min(displayStart, len))
            )
            setSelectedRange(displaySel)
        } else {
            let displayCursor = rawOffsetToDisplayOffset(cursorInRaw)
            let clamped = min(displayCursor, textStorage!.length)
            setSelectedRange(NSRange(location: clamped, length: 0))
        }

        typingAttributes = baseAttributes
        isUpdating = false
    }

    // MARK: - Coordinate Mapping (display ↔ rawSource)

    private func blockIndexForRawOffset(_ rawOffset: Int) -> Int? {
        for (i, block) in blocks.enumerated() {
            if rawOffset >= block.range.location && rawOffset <= block.range.upperBound {
                return i
            }
        }
        return blocks.isEmpty ? nil : blocks.count - 1
    }

    private func displayOffsetToRawOffset(_ displayOffset: Int) -> Int {
        for (i, displayRange) in displayRanges.enumerated() {
            guard i < blocks.count else { break }
            let block = blocks[i]

            if displayOffset <= displayRange.upperBound {
                let offsetInBlock = max(0, displayOffset - displayRange.location)

                if i == activeBlockIndex {
                    let clampedOffset = min(offsetInBlock, (block.content as NSString).length)
                    return block.range.location + clampedOffset
                } else {
                    let displayLen = displayRange.length
                    let rawLen = (block.content as NSString).length
                    if displayLen > 0 {
                        let proportion = Double(offsetInBlock) / Double(displayLen)
                        let mapped = Int(proportion * Double(rawLen))
                        return block.range.location + min(mapped, rawLen)
                    }
                    return block.range.location
                }
            }

            let separatorEnd = (i + 1 < displayRanges.count)
                ? displayRanges[i + 1].location
                : (textStorage?.length ?? displayRange.upperBound)
            if displayOffset < separatorEnd {
                let sepOffset = displayOffset - displayRange.upperBound
                return block.range.upperBound + sepOffset
            }
        }

        return (rawSource as NSString).length
    }

    private func rawOffsetToDisplayOffset(_ rawOffset: Int) -> Int {
        for (i, block) in blocks.enumerated() {
            guard i < displayRanges.count else { break }
            let displayRange = displayRanges[i]

            if rawOffset <= block.range.upperBound {
                let offsetInBlock = max(0, rawOffset - block.range.location)

                if i == activeBlockIndex {
                    return displayRange.location + min(offsetInBlock, displayRange.length)
                } else {
                    let rawLen = (block.content as NSString).length
                    if rawLen > 0 {
                        let proportion = Double(offsetInBlock) / Double(rawLen)
                        let mapped = Int(proportion * Double(displayRange.length))
                        return displayRange.location + min(mapped, displayRange.length)
                    }
                    return displayRange.location
                }
            }

            let nextRawStart = (i + 1 < blocks.count)
                ? blocks[i + 1].range.location
                : (rawSource as NSString).length
            if rawOffset < nextRawStart {
                let sepOffset = rawOffset - block.range.upperBound
                return displayRange.upperBound + sepOffset
            }
        }

        return textStorage?.length ?? 0
    }

    private func displayRangeToRawRange(_ displayRange: NSRange) -> NSRange {
        let rawStart = displayOffsetToRawOffset(displayRange.location)
        let rawEnd = displayOffsetToRawOffset(displayRange.location + displayRange.length)
        return NSRange(location: rawStart, length: max(0, rawEnd - rawStart))
    }

    // MARK: - Markdown Rendering

    private func renderMarkdown(_ markdown: String) -> NSAttributedString {
        if let attrStr = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            let ns = NSMutableAttributedString(attrStr)
            ns.enumerateAttribute(.font, in: NSRange(location: 0, length: ns.length)) { value, range, _ in
                let existingFont = value as? NSFont ?? bodyFont
                let traits = existingFont.fontDescriptor.symbolicTraits

                var targetFont = bodyFont
                if traits.contains(.bold) && traits.contains(.italic) {
                    targetFont = NSFontManager.shared.convert(bodyFont, toHaveTrait: [.boldFontMask, .italicFontMask])
                } else if traits.contains(.bold) {
                    targetFont = NSFontManager.shared.convert(bodyFont, toHaveTrait: .boldFontMask)
                } else if traits.contains(.italic) {
                    targetFont = NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask)
                }
                ns.addAttribute(.font, value: targetFont, range: range)
            }
            let fullRange = NSRange(location: 0, length: ns.length)
            ns.addAttribute(.paragraphStyle, value: bodyParagraphStyle, range: fullRange)
            ns.addAttribute(.foregroundColor, value: NSColor.black, range: fullRange)
            return ns
        }

        return NSAttributedString(string: markdown, attributes: baseAttributes)
    }
}

// MARK: - String UTF-16 Index Helper

extension String {
    func utf16Index(at offset: Int) -> String.Index {
        return String.Index(utf16Offset: offset, in: self)
    }
}
