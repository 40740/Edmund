import AppKit

// MARK: - Line numbers
//
// Source line numbers, off by default (Settings ▸ Edit ▸ Lines). Two placements
// share one walk over the visible lines:
//
//   - **Beside the content** (the default): drawn in the reading column's own
//     margin on the text view's background pass. Reserves nothing, so the column
//     never moves, and the numbers stay next to the line they label at any
//     window width.
//   - **By the window edge** (`lineNumbersByWindowEdge`): a `LineNumberRulerView`
//     on the scroll view. AppKit owns the scroll sync and clipping, but it
//     reserves width, so the centered column re-centers when it is switched on.
//
// Also here: `lineStarts`, the cached line-start table backing
// `line(forOffset:)` / `offset(forLine:)`, dropped on every `rawSource` write.
//
// Read mode is unaffected — it hides the whole scroll view, ruler included. So
// is printing: the ruler isn't part of the text view, and the in-margin numbers
// draw only for the on-screen viewport.

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

    // MARK: Shared drawing pieces

    /// How the numbers are inked, plus the two metrics both placements need.
    struct LineNumberStyle {
        let attributes: [NSAttributedString.Key: Any]
        /// Distance from the top `draw(at:)` expects down to the baseline.
        /// `draw(at:)` takes the top of the line box, and NSStringDrawing lays
        /// out a box taller than ascender + descender (20 pt for the 14 pt mono
        /// here) — derive the drop from the height it actually uses, or every
        /// number sits a few points low against its line.
        let topToBaseline: CGFloat
        /// A monospace face gives every digit the same advance, which is what
        /// lets the numbers be right-aligned without measuring each one.
        let digitWidth: CGFloat
    }

    var lineNumberStyle: LineNumberStyle {
        let font = theme.monospaceFont()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: syntaxDimColor
        ]
        let digit = NSAttributedString(string: "0", attributes: attributes)
        return LineNumberStyle(attributes: attributes,
                               topToBaseline: digit.size().height + font.descender,
                               digitWidth: digit.size().width)
    }

    /// Calls `body` once per visible source line, with its 1-indexed number and
    /// the baseline of its **first** visual line in text-container coordinates
    /// (so a wrapped line is numbered once, at its top).
    ///
    /// Walks the viewport the text view has *already* laid out. Forcing layout
    /// instead (`.ensuresLayout`, or enumerating from the document start)
    /// re-enters the viewport layout controller mid-draw, which blanks the text
    /// view — and on a large document it would lay out the whole thing, the trap
    /// `lineRect(forCharacterAt:)` documents.
    func enumerateVisibleLineNumbers(_ body: (Int, CGFloat) -> Void) {
        guard let tlm = textLayoutManager,
              let viewport = tlm.textViewportLayoutController.viewportRange
        else { return }
        let bottom = visibleRect.maxY - textContainerOrigin.y
        // Lines shorter than this are hidden by rendering (a table's separator
        // row, some delimiters — 0.01 pt `hiddenFont`). They still hold a line
        // number, but drawing it would stack it on the neighbor's, so the
        // visible sequence is allowed to skip.
        let minimumDrawnHeight = bodyFont.pointSize / 2
        var lastLine = 0

        tlm.enumerateTextLayoutFragments(from: viewport.location,
                                         options: []) { fragment in
            let frame = fragment.layoutFragmentFrame
            guard frame.minY <= bottom else { return false }
            guard let firstLine = fragment.textLineFragments.first else { return true }

            let offset = tlm.offset(from: tlm.documentRange.location,
                                    to: fragment.rangeInElement.location)
            let line = self.line(forOffset: offset)
            // A paragraph is normally one fragment, but don't repeat a number if
            // TextKit ever splits one — the first fragment owns the line.
            guard line != lastLine,
                  firstLine.typographicBounds.height >= minimumDrawnHeight
            else { return true }
            lastLine = line

            body(line, frame.minY + firstLine.typographicBounds.minY
                     + firstLine.glyphOrigin.y)
            return true
        }
    }

    /// Space between the numbers and what they sit beside.
    static let lineNumberPadding: CGFloat = 8

    // MARK: In-margin numbers (the default placement)

    /// Draws the numbers in the reading column's left margin, right-aligned just
    /// short of the text. Called from `drawBackground(in:)` — they occupy margin
    /// the text never uses, so nothing has to move to make room.
    func drawLineNumbersBesideContent(in rect: NSRect) {
        let style = lineNumberStyle
        let origin = textContainerOrigin
        // The column's text starts a `lineFragmentPadding` inside the container.
        let padding = textContainer?.lineFragmentPadding ?? 0
        let rightEdge = origin.x + padding - Self.lineNumberPadding

        // ponytail: a window narrow enough to squeeze the margin out drops the
        // numbers rather than printing them over the text — all of them, judged
        // by the document's widest, so they never go ragged (the 3-digit ones
        // vanishing while the 1-digit ones stay). Reach for the window-edge
        // gutter instead if they must always be visible.
        let widest = style.digitWidth
            * CGFloat(LineNumberRulerView.digitCount(lineStarts.count))
        guard rightEdge - widest >= 0 else { return }

        enumerateVisibleLineNumbers { line, baseline in
            let label = NSAttributedString(string: "\(line)", attributes: style.attributes)
            let x = rightEdge - style.digitWidth * CGFloat(label.length)
            let y = origin.y + baseline - style.topToBaseline
            guard rect.intersects(NSRect(x: x, y: y, width: rightEdge - x,
                                         height: style.topToBaseline)) else { return }
            label.draw(at: NSPoint(x: x, y: y))
        }
    }

    // MARK: Gutter install / remove

    /// Installs or removes the window-edge gutter. Only that placement uses a
    /// ruler; the in-margin default draws itself. A no-op until the view is
    /// inside a scroll view — Document configures the editor before adding it to
    /// one, so `viewDidMoveToSuperview` replays this.
    func updateLineNumberRuler() {
        guard let scrollView = enclosingScrollView else { return }
        if showLineNumbers && lineNumbersByWindowEdge {
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
        needsDisplay = true
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateLineNumberRuler()
    }
}

/// The window-edge line-number gutter. Numbers are dimmed, monospaced, and
/// right-aligned; nothing separates the gutter from the text but space — no
/// rule, and the same background, so the two read as one surface.
final class LineNumberRulerView: NSRulerView {

    /// Never narrower than this many digits, so the gutter doesn't twitch as a
    /// short document crosses 9 → 10 lines.
    private static let minimumDigits = 3

    private var editor: EditorTextView? { clientView as? EditorTextView }

    init(scrollView: NSScrollView, editor: EditorTextView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        // Against the macOS 14 SDK `clipsToBounds` defaults to false, and the
        // rect handed to `drawHashMarksAndLabels` is wider than the gutter — so
        // without this the background fill paints over the whole scroll view and
        // the document goes blank.
        clipsToBounds = true
        clientView = editor
        ruleThickness = Self.thickness(digits: Self.minimumDigits,
                                       font: editor.theme.monospaceFont())
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Gutter width for a number of digits, from the monospace font's own digit
    /// advance.
    @MainActor static func thickness(digits: Int, font: NSFont) -> CGFloat {
        let digitWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
        return CGFloat(max(digits, minimumDigits)) * digitWidth
            + 2 * EditorTextView.lineNumberPadding
    }

    /// Digits needed to write `count`.
    static func digitCount(_ count: Int) -> Int {
        var digits = 1
        var remaining = count
        while remaining >= 10 { remaining /= 10; digits += 1 }
        return digits
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let editor else { return }

        // The scroll view draws no background and, in dark mode, the editor
        // paints its own #292929 — so match it here, or the window's gray shows
        // through and the gutter reads as a separate panel.
        editor.editorBackgroundColor.setFill()
        rect.fill()

        let style = editor.lineNumberStyle
        let needed = Self.thickness(digits: Self.digitCount(editor.lineStarts.count),
                                    font: editor.theme.monospaceFont())
        if abs(needed - ruleThickness) > 0.5 {
            // Re-tiles the scroll view, which can't happen mid-draw — land it on
            // the next runloop pass instead.
            RunLoop.main.perform { [weak self] in
                MainActor.assumeIsolated { self?.ruleThickness = needed }
            }
        }

        // Fragment baselines are in text-container space; the ruler's own space
        // is offset from the text view's by both views' geometry.
        let rulerOffsetY = convert(NSPoint.zero, from: editor).y
            + editor.textContainerOrigin.y
        let rightEdge = ruleThickness - EditorTextView.lineNumberPadding

        editor.enumerateVisibleLineNumbers { line, baseline in
            let label = NSAttributedString(string: "\(line)", attributes: style.attributes)
            label.draw(at: NSPoint(x: rightEdge - style.digitWidth * CGFloat(label.length),
                                   y: rulerOffsetY + baseline - style.topToBaseline))
        }
    }
}
