import AppKit

// MARK: - Line numbers
//
// A source-line gutter at the left edge of the window, off by default
// (Settings ▸ Edit ▸ Lines). Three pieces live here because none is useful
// without the others:
//
//   - `lineStarts`, a cached line-start table backing `line(forOffset:)` and
//     `offset(forLine:)`. Dropped on every `rawSource` write.
//   - `LineNumberRulerView`, an NSRulerView that draws one number per source
//     line beside the line's first visual line.
//   - `updateLineNumberRuler()`, which installs/removes it on the scroll view.
//
// The gutter is reserved space, not an overlay: AppKit owns the scroll sync and
// clipping, and the numbers can never collide with the text. It narrows the text
// view, so the centered reading column re-centers when the setting is toggled.
//
// Read mode is unaffected — it hides the whole scroll view, ruler included. So
// is printing: the ruler isn't part of the text view, so it never prints.

extension EditorTextView {

    // MARK: Line-start table

    /// UTF-16 offset of each line's first character, `lineStarts[0] == 0`. Built
    /// lazily and dropped by `rawSource`'s `didSet`, which turns line ↔ offset
    /// lookups into a binary search: the gutter does one per fragment per
    /// redraw, and the status bar one per keystroke. Both were linear scans of
    /// the whole document before.
    ///
    /// A document ending in a newline gets a final entry equal to its length —
    /// the empty last line, matching how the editor counts lines everywhere.
    var lineStarts: [Int] {
        if let lineStartsCache { return lineStartsCache }
        var starts = [0]
        var offset = 0
        for unit in rawSource.utf16 {
            offset += 1
            if unit == 0x000A { starts.append(offset) }
        }
        lineStartsCache = starts
        return starts
    }

    /// 1-indexed source line containing character `offset` (counts "\n" only —
    /// matches swift-markdown's SourceLocation convention; no CRLF handling,
    /// same as the rest of the pipeline). An offset past the end reports the
    /// last line; a negative one reports line 1.
    public func line(forOffset offset: Int) -> Int {
        let starts = lineStarts
        let target = max(0, offset)
        // Largest index whose start is still <= target.
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= target { low = mid } else { high = mid - 1 }
        }
        return low + 1
    }

    /// Character offset of the start of 1-indexed `line`, clamped to the
    /// document (line < 1 → 0; past the last line → start of the last line).
    public func offset(forLine line: Int) -> Int {
        let starts = lineStarts
        guard line > 1 else { return 0 }
        guard line <= starts.count else { return starts[starts.count - 1] }
        return starts[line - 1]
    }

    // MARK: Gutter install / remove

    /// Installs or removes the gutter to match `showLineNumbers`. A no-op until
    /// the view is inside a scroll view — Document configures the editor before
    /// adding it to one, so `viewDidMoveToSuperview` replays this.
    func updateLineNumberRuler() {
        guard let scrollView = enclosingScrollView else { return }
        if showLineNumbers {
            guard lineNumberRuler == nil else { return }
            let ruler = LineNumberRulerView(scrollView: scrollView, editor: self)
            scrollView.verticalRulerView = ruler
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = true
            lineNumberRuler = ruler
        } else {
            guard lineNumberRuler != nil else { return }
            scrollView.rulersVisible = false
            scrollView.hasVerticalRuler = false
            scrollView.verticalRulerView = nil
            lineNumberRuler = nil
        }
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateLineNumberRuler()
    }
}

/// The line-number gutter. Numbers are dimmed, monospaced, and right-aligned;
/// nothing separates the gutter from the text but space — no rule, and the same
/// background, so the two read as one surface.
final class LineNumberRulerView: NSRulerView {

    /// Space either side of the digits.
    private static let padding: CGFloat = 8

    /// Never narrower than this many digits, so the gutter doesn't twitch as a
    /// short document crosses 9 → 10 lines.
    private static let minimumDigits = 3

    private var editor: EditorTextView? { clientView as? EditorTextView }

    init(scrollView: NSScrollView, editor: EditorTextView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = editor
        ruleThickness = Self.thickness(digits: Self.minimumDigits,
                                       font: editor.theme.monospaceFont())
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Gutter width for a number of digits, from the monospace font's own digit
    /// advance (every digit is the same width, which is why the numbers can be
    /// right-aligned without measuring each one).
    @MainActor static func thickness(digits: Int, font: NSFont) -> CGFloat {
        let digitWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
        return CGFloat(max(digits, minimumDigits)) * digitWidth + 2 * padding
    }

    /// Digits needed to write `count`.
    static func digitCount(_ count: Int) -> Int {
        var digits = 1
        var remaining = count
        while remaining >= 10 { remaining /= 10; digits += 1 }
        return digits
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let editor, let tlm = editor.textLayoutManager else { return }

        // The scroll view draws no background and, in dark mode, the editor
        // paints its own #292929 — so match it here, or the window's gray shows
        // through and the gutter reads as a separate panel.
        editor.editorBackgroundColor.setFill()
        rect.fill()

        let font = editor.theme.monospaceFont()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: editor.syntaxDimColor
        ]

        let needed = Self.thickness(digits: Self.digitCount(editor.lineStarts.count),
                                    font: font)
        if abs(needed - ruleThickness) > 0.5 {
            // Re-tiles the scroll view, which can't happen mid-draw — land it on
            // the next runloop pass instead.
            RunLoop.main.perform { [weak self] in
                MainActor.assumeIsolated { self?.ruleThickness = needed }
            }
        }

        // Fragment frames are in text-container space; the ruler's own space is
        // offset from the text view's by both views' geometry.
        let containerOriginY = editor.textContainerOrigin.y
        let rulerOffsetY = convert(NSPoint.zero, from: editor).y + containerOriginY
        let visible = editor.visibleRect
        let top = max(0, visible.minY - containerOriginY)
        let bottom = visible.maxY - containerOriginY

        guard let start = tlm.textLayoutFragment(for: CGPoint(x: 0, y: top)) else { return }
        // Lines shorter than this are hidden by rendering (a table's separator
        // row, some delimiters — 0.01 pt `hiddenFont`). They still hold a line
        // number, but drawing it would stack it on the neighbor's, so the
        // visible sequence is allowed to skip.
        let minimumDrawnHeight = editor.bodyFont.pointSize / 2
        var lastDrawnLine = 0

        tlm.enumerateTextLayoutFragments(from: start.rangeInElement.location,
                                         options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            guard frame.minY <= bottom else { return false }
            guard let firstLine = fragment.textLineFragments.first else { return true }

            let offset = tlm.offset(from: tlm.documentRange.location,
                                    to: fragment.rangeInElement.location)
            let line = editor.line(forOffset: offset)
            // A paragraph is normally one fragment, but don't repeat a number if
            // TextKit ever splits one — the first fragment owns the line.
            guard line != lastDrawnLine,
                  firstLine.typographicBounds.height >= minimumDrawnHeight
            else { return true }
            lastDrawnLine = line

            let baseline = frame.minY + firstLine.typographicBounds.minY
                + firstLine.glyphOrigin.y
            let label = NSAttributedString(string: "\(line)", attributes: attributes)
            label.draw(at: NSPoint(x: self.ruleThickness - Self.padding - label.size().width,
                                   y: rulerOffsetY + baseline - font.ascender))
            return true
        }
    }
}
