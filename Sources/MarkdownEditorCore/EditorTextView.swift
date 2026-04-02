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
    var isUpdating = false
    var displayRanges: [NSRange] = []
    private var pendingRecompose = false

    // MARK: - Custom Undo/Redo State

    struct UndoSnapshot {
        let rawSource: String
        let cursorInRaw: Int
    }

    enum EditType { case insert, delete, other }

    var undoStack: [UndoSnapshot] = []
    var redoStack: [UndoSnapshot] = []
    var lastEditBlockIndex: Int? = nil
    var lastEditType: EditType = .other
    var isUndoRedoing = false

    /// The separator between blocks in the display.
    /// Must match what BlockParser splits on.
    let blockSeparator = "\n"

    // MARK: - Colors (semantic — adapts to light/dark mode)

    let accentColor = NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.9, alpha: 1.0)

    /// Foreground color for all body text. Uses the system text color so it
    /// flips automatically between near-black (light) and near-white (dark).
    var foregroundColor: NSColor { .textColor }

    /// Background color for the editor surface. `.textBackgroundColor` is the
    /// standard semantic color for text-editing backgrounds (white / dark gray).
    private var editorBackgroundColor: NSColor { .textBackgroundColor }

    // MARK: - Fonts & Style

    let bodyFont: NSFont = {
        if let ia = NSFont(name: "iA Writer Mono S", size: 16) { return ia }
        return NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
    }()

    let bodyParagraphStyle: NSParagraphStyle = {
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 6
        ps.paragraphSpacing = 0
        return ps
    }()

    var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: foregroundColor,
            .paragraphStyle: bodyParagraphStyle,
        ]
    }

    var separatorLength: Int { (blockSeparator as NSString).length }

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
        recompose(cursorInRaw: currentCursorInRaw())
    }

    // MARK: - Edit Flow

    public override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        if isUpdating { return false }
        if let replacement = replacementString {
            if !isUndoRedoing {
                recordUndoIfNeeded(editRange: affectedCharRange, replacement: replacement)
            }
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

        let sel = selectedRange()
        let cursorInBlock = max(0, sel.location - safeStart)
        let rawCursor = blocks[activeIdx].range.location
            + min(cursorInBlock, (newActiveContent as NSString).length)

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

        let clampedRawCursor = min(rawCursor, (rawSource as NSString).length)
        let newBlockIndex = blockIndexForRawOffset(clampedRawCursor)
        if newBlockIndex != activeBlockIndex {
            recompose(cursorInRaw: clampedRawCursor)
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

    // MARK: - Helpers

    func currentCursorInRaw() -> Int {
        let sel = selectedRange()
        return displayOffsetToRawOffset(sel.location)
    }
}

// MARK: - String UTF-16 Index Helper

extension String {
    func utf16Index(at offset: Int) -> String.Index {
        return String.Index(utf16Offset: offset, in: self)
    }
}
