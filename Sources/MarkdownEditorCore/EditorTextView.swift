import AppKit

/// A single NSTextView that renders each paragraph block as either:
///   - **Rich text** (rendered markdown) — for non-active blocks
///   - **Raw markdown** — for the block containing the cursor
///
/// ## Architecture
///
/// `rawSource` is the **sole source of truth** for the document content.
/// The text storage is a display output rebuilt from rawSource.
///
/// **Edits** flow through NSTextView's normal path:
///   1. `shouldChangeText` records an undo snapshot (coalesced), returns `true`
///   2. NSTextView applies the edit to the text storage
///   3. `didChangeText` fires — we sync `rawSource` from the text storage
///
/// **Cursor movement** is detected via `didChangeSelectionNotification`.
/// When the cursor moves to a different block, we do a full recompose
/// (async, after the event finishes) to render/unrender blocks.
///
/// **Undo/Redo** uses custom stacks of `rawSource` snapshots, completely
/// bypassing NSTextView's built-in undo.  This avoids the fundamental
/// problem where `recompose` (which replaces the entire text storage)
/// invalidates NSUndoManager's position-based undo actions.
public class EditorTextView: NSTextView {

    // MARK: - State (internal for @testable import)

    var rawSource: String = ""
    var blocks: [Block] = []
    var activeBlockIndex: Int? = nil
    private var isUpdating = false
    var displayRanges: [NSRange] = []
    private var pendingRecompose = false

    // MARK: - Custom Undo/Redo

    struct UndoSnapshot {
        let rawSource: String
        let cursorInRaw: Int
    }

    enum EditType { case insert, delete, other }

    var undoStack: [UndoSnapshot] = []
    var redoStack: [UndoSnapshot] = []
    private var lastEditBlockIndex: Int? = nil
    private var lastEditType: EditType = .other
    private var isUndoRedoing = false

    /// The separator between blocks in the display.
    /// Must match what BlockParser splits on.
    private let blockSeparator = "\n"

    // MARK: - Colors (semantic — adapts to light/dark mode)

    private let accentColor = NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.9, alpha: 1.0)

    /// Foreground color for all body text. Uses the system text color so it
    /// flips automatically between near-black (light) and near-white (dark).
    private var foregroundColor: NSColor { .textColor }

    /// Background color for the editor surface. `.textBackgroundColor` is the
    /// standard semantic color for text-editing backgrounds (white / dark gray).
    private var editorBackgroundColor: NSColor { .textBackgroundColor }

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
            .foregroundColor: foregroundColor,
            .paragraphStyle: bodyParagraphStyle,
        ]
    }

    private var separatorLength: Int { (blockSeparator as NSString).length }

    // MARK: - Initialization

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    public override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isRichText = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        allowsUndo = false

        backgroundColor = editorBackgroundColor
        insertionPointColor = foregroundColor
        selectedTextAttributes = [
            .backgroundColor: accentColor.withAlphaComponent(0.3),
            .foregroundColor: foregroundColor,
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

    // MARK: - Appearance

    /// Re-render when the system appearance (light ↔ dark) changes.
    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        backgroundColor = editorBackgroundColor
        insertionPointColor = foregroundColor
        selectedTextAttributes = [
            .backgroundColor: accentColor.withAlphaComponent(0.3),
            .foregroundColor: foregroundColor,
        ]
        typingAttributes = baseAttributes
        // Re-render all blocks so text color updates
        recompose(cursorInRaw: currentCursorInRaw())
    }

    // MARK: - Undo / Redo
    //
    // Custom undo stack operating on rawSource snapshots.  Completely bypasses
    // NSTextView's built-in undo (allowsUndo = false) because recompose
    // replaces the entire text storage, invalidating position-based undo.

    @objc func undo(_ sender: Any?) {
        performUndo()
    }

    @objc func redo(_ sender: Any?) {
        performRedo()
    }

    private func currentCursorInRaw() -> Int {
        let sel = selectedRange()
        return displayOffsetToRawOffset(sel.location)
    }

    private func classifyEdit(range: NSRange, replacement: String) -> EditType {
        if replacement == "\n" { return .other }  // Enter always starts a new group
        if replacement.count == 1 && range.length == 0 { return .insert }
        if replacement.isEmpty && range.length == 1 { return .delete }
        return .other
    }

    /// Push an undo snapshot if this edit starts a new coalescing group.
    private func recordUndoIfNeeded(editRange: NSRange, replacement: String) {
        let editType = classifyEdit(range: editRange, replacement: replacement)

        let shouldPush = undoStack.isEmpty
            || editType == .other
            || editType != lastEditType
            || activeBlockIndex != lastEditBlockIndex

        if shouldPush {
            undoStack.append(UndoSnapshot(rawSource: rawSource, cursorInRaw: currentCursorInRaw()))
            redoStack.removeAll()
        }

        lastEditType = editType
        lastEditBlockIndex = activeBlockIndex
    }

    private func performUndo() {
        guard let snapshot = undoStack.popLast() else { return }
        // Save current state for redo
        redoStack.append(UndoSnapshot(rawSource: rawSource, cursorInRaw: currentCursorInRaw()))
        restoreSnapshot(snapshot)
    }

    private func performRedo() {
        guard let snapshot = redoStack.popLast() else { return }
        // Save current state for undo
        undoStack.append(UndoSnapshot(rawSource: rawSource, cursorInRaw: currentCursorInRaw()))
        restoreSnapshot(snapshot)
    }

    private func restoreSnapshot(_ snapshot: UndoSnapshot) {
        isUndoRedoing = true
        rawSource = snapshot.rawSource
        blocks = BlockParser.parse(rawSource, previous: blocks)
        recompose(cursorInRaw: snapshot.cursorInRaw)
        isUndoRedoing = false
        // Reset coalescing so the next edit starts a fresh group
        lastEditType = .other
        lastEditBlockIndex = nil
    }

    // MARK: - Edit Flow

    public override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        if isUpdating { return false }
        if let replacement = replacementString {
            if !isUndoRedoing {
                recordUndoIfNeeded(editRange: affectedCharRange, replacement: replacement)
            }
            // If the edit touches a separator between blocks (e.g. backspace
            // at start of a block deleting the \n), handle it directly on
            // rawSource. NSTextView can't sync this back through the normal
            // didChangeText path because displayRanges become stale.
            if editTouchesSeparator(range: affectedCharRange) {
                handleSeparatorEdit(displayRange: affectedCharRange, replacement: replacement)
                return false
            }
        }
        return true
    }

    /// Returns true if the edit range overlaps a separator gap between blocks.
    private func editTouchesSeparator(range: NSRange) -> Bool {
        guard displayRanges.count > 1 else { return false }
        for i in 0..<(displayRanges.count - 1) {
            let gapStart = displayRanges[i].upperBound
            let gapEnd = displayRanges[i + 1].location
            if range.location < gapEnd && range.upperBound > gapStart {
                return true
            }
        }
        return false
    }

    /// Applies an edit that crosses a block separator directly to rawSource,
    /// then re-parses and recomposes.
    private func handleSeparatorEdit(displayRange editRange: NSRange, replacement: String) {
        let rawStart = displayOffsetToRawOffset(editRange.location)
        let rawEnd = displayOffsetToRawOffset(editRange.location + editRange.length)
        let rawRange = NSRange(location: rawStart, length: max(0, rawEnd - rawStart))

        let nsRaw = rawSource as NSString
        rawSource = nsRaw.replacingCharacters(in: rawRange, with: replacement)

        let newCursorRaw = rawStart + (replacement as NSString).length
        blocks = BlockParser.parse(rawSource, previous: blocks)
        recompose(cursorInRaw: newCursorRaw)
    }

    public override func didChangeText() {
        super.didChangeText()
        guard !isUpdating, !isUndoRedoing else { return }
        syncRawSourceFromDisplay()
        applySyntaxHighlighting()
    }

    /// Reads the active block's content from the text storage and rebuilds rawSource.
    private func syncRawSourceFromDisplay() {
        guard let ts = textStorage else { return }
        let displayString = ts.string as NSString

        if blocks.isEmpty || displayRanges.isEmpty {
            rawSource = ts.string
            blocks = BlockParser.parse(rawSource)
            return
        }

        guard let activeIdx = activeBlockIndex, activeIdx < displayRanges.count else {
            rawSource = ts.string
            blocks = BlockParser.parse(rawSource)
            return
        }

        // Compute the active block's current display range.
        // It starts after the separator following the previous block,
        // and ends before the separator preceding the next block.
        let activeDisplayStart: Int
        if activeIdx == 0 {
            activeDisplayStart = 0
        } else {
            activeDisplayStart = displayRanges[activeIdx - 1].upperBound + separatorLength
        }

        let activeDisplayEnd: Int
        if activeIdx == displayRanges.count - 1 {
            activeDisplayEnd = displayString.length
        } else {
            // Use suffix lengths — non-active block lengths are correct even
            // though their positions are stale after the active block changed size.
            var suffixLength = 0
            for i in (activeIdx + 1)..<displayRanges.count {
                suffixLength += separatorLength + displayRanges[i].length
            }
            activeDisplayEnd = displayString.length - suffixLength
        }

        let safeStart = max(0, activeDisplayStart)
        let safeEnd = max(safeStart, min(activeDisplayEnd, displayString.length))
        let activeDisplayRange = NSRange(location: safeStart, length: safeEnd - safeStart)

        let newActiveContent = displayString.substring(with: activeDisplayRange)

        // Compute raw cursor offset while the block mapping is still valid.
        let sel = selectedRange()
        let cursorInBlock = max(0, sel.location - safeStart)
        let rawCursor = blocks[activeIdx].range.location
            + min(cursorInBlock, (newActiveContent as NSString).length)

        // Rebuild rawSource by replacing the active block's content.
        var parts: [String] = []
        for (i, block) in blocks.enumerated() {
            if i == activeIdx {
                parts.append(newActiveContent)
            } else {
                parts.append(block.content)
            }
        }
        rawSource = parts.joined(separator: blockSeparator)

        blocks = BlockParser.parse(rawSource, previous: blocks)
        recalcDisplayRanges()

        // If the cursor is now in a different block (e.g., Enter split a block
        // or Backspace merged blocks), recompose to update rendering.
        let clampedRawCursor = min(rawCursor, (rawSource as NSString).length)
        let newBlockIndex = blockIndexForRawOffset(clampedRawCursor)
        if newBlockIndex != activeBlockIndex {
            recompose(cursorInRaw: clampedRawCursor)
        }
    }

    /// Recalculates displayRanges from current blocks without touching textStorage.
    private func recalcDisplayRanges() {
        displayRanges = []
        var offset = 0
        for (i, block) in blocks.enumerated() {
            if i > 0 {
                offset += separatorLength
            }
            let displayLen: Int
            if i == activeBlockIndex {
                displayLen = (block.content as NSString).length
            } else {
                let rendered = renderMarkdown(block.content)
                displayLen = rendered.length
            }
            displayRanges.append(NSRange(location: offset, length: displayLen))
            offset += displayLen
        }
    }

    // MARK: - Selection Change Detection

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

                let currentSel = self.selectedRange()
                let rawStart = self.displayOffsetToRawOffset(currentSel.location)
                let rawEnd = self.displayOffsetToRawOffset(currentSel.location + currentSel.length)
                let rawSel = NSRange(location: rawStart, length: rawEnd - rawStart)
                self.recompose(cursorInRaw: rawStart, selectionInRaw: rawSel)
            }
        }
    }

    // MARK: - Display Composition (full recompose)
    //
    // Called when the active block changes.  Replaces the entire text storage.

    func recompose(cursorInRaw: Int, selectionInRaw: NSRange? = nil) {
        isUpdating = true

        activeBlockIndex = blockIndexForRawOffset(cursorInRaw)

        let composed = NSMutableAttributedString()
        displayRanges = []

        for (i, block) in blocks.enumerated() {
            if i > 0 {
                composed.append(NSAttributedString(string: blockSeparator, attributes: baseAttributes))
            }

            let blockDisplayStart = composed.length

            if i == activeBlockIndex {
                composed.append(highlightSyntax(block.content))
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

    // MARK: - Coordinate Mapping

    func blockIndexForRawOffset(_ rawOffset: Int) -> Int? {
        for (i, block) in blocks.enumerated() {
            if rawOffset >= block.range.location && rawOffset <= block.range.upperBound {
                return i
            }
        }
        return blocks.isEmpty ? nil : blocks.count - 1
    }

    func displayOffsetToRawOffset(_ displayOffset: Int) -> Int {
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

    func rawOffsetToDisplayOffset(_ rawOffset: Int) -> Int {
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

    // MARK: - Active Block Syntax Highlighting

    /// Color for dimmed syntax delimiters (*, **, `, #, etc.)
    private var syntaxDimColor: NSColor { .tertiaryLabelColor }

    /// Builds an NSAttributedString of the raw markdown with syntax highlighting.
    ///
    /// Uses `swift-markdown` (cmark-gfm) to parse the source, then maps the
    /// AST's source ranges back onto the raw text: bold/italic font traits on
    /// content, dimmed color on delimiters.  Because the same parser powers
    /// `AttributedString(markdown:)`, the active block's highlighting is
    /// consistent with rendered (non-active) blocks — including edge cases
    /// like mismatched delimiters (`**hi*`).
    func highlightSyntax(_ markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: markdown, attributes: baseAttributes)
        let spans = SyntaxHighlighter.parse(markdown)

        for span in spans {
            // Dim delimiter characters
            for dr in span.delimiterRanges {
                guard dr.upperBound <= result.length else { continue }
                result.addAttribute(.foregroundColor, value: syntaxDimColor, range: dr)
            }

            switch span.kind {
            case .bold:
                guard span.contentRange.upperBound <= result.length else { continue }
                let bold = NSFontManager.shared.convert(bodyFont, toHaveTrait: .boldFontMask)
                result.addAttribute(.font, value: bold, range: span.contentRange)

            case .italic:
                guard span.contentRange.upperBound <= result.length else { continue }
                let italic = NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask)
                result.addAttribute(.font, value: italic, range: span.contentRange)

            case .boldItalic:
                guard span.contentRange.upperBound <= result.length else { continue }
                let bi = NSFontManager.shared.convert(bodyFont, toHaveTrait: [.boldFontMask, .italicFontMask])
                result.addAttribute(.font, value: bi, range: span.contentRange)

            case .code:
                break

            case .heading(let level):
                guard span.fullRange.upperBound <= result.length else { continue }
                let scale: CGFloat = level == 1 ? 1.5 : level == 2 ? 1.3 : level == 3 ? 1.15 : 1.0
                let sized = NSFont(descriptor: bodyFont.fontDescriptor,
                                   size: bodyFont.pointSize * scale) ?? bodyFont
                let heading = NSFontManager.shared.convert(sized, toHaveTrait: .boldFontMask)
                result.addAttribute(.font, value: heading, range: span.fullRange)
                // Re-dim delimiters (they got heading font above)
                for dr in span.delimiterRanges {
                    guard dr.upperBound <= result.length else { continue }
                    result.addAttribute(.foregroundColor, value: syntaxDimColor, range: dr)
                }
            }
        }

        return result
    }

    /// Re-applies syntax highlighting to the active block in the text storage.
    /// Called after each keystroke to keep formatting in sync with content.
    private func applySyntaxHighlighting() {
        guard let ts = textStorage,
              let activeIdx = activeBlockIndex,
              activeIdx < displayRanges.count,
              activeIdx < blocks.count else { return }

        let displayRange = displayRanges[activeIdx]
        guard displayRange.upperBound <= ts.length else { return }

        let content = blocks[activeIdx].content
        let highlighted = highlightSyntax(content)
        let offset = displayRange.location

        isUpdating = true
        ts.beginEditing()

        // Transfer all attributes from the highlighted string to text storage
        highlighted.enumerateAttributes(in: NSRange(location: 0, length: highlighted.length), options: []) { attrs, range, _ in
            let displayR = NSRange(location: range.location + offset, length: range.length)
            ts.setAttributes(attrs, range: displayR)
        }

        ts.endEditing()
        isUpdating = false

        typingAttributes = baseAttributes
    }

    // MARK: - Markdown Rendering

    func renderMarkdown(_ markdown: String) -> NSAttributedString {
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
            ns.addAttribute(.foregroundColor, value: foregroundColor, range: fullRange)
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
