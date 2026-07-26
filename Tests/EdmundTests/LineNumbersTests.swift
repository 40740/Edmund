import Testing
import AppKit
@testable import EdmundCore

// The line-number gutter's headless half: the cached line-start table behind
// `line(forOffset:)` / `offset(forLine:)`, and the gutter's width math. The
// drawing itself is verified on screen.
@Suite("Line numbers")
@MainActor
struct LineNumbersTests {

    @Test("Offsets map to their 1-indexed line")
    func offsetToLine() {
        let editor = makeEditor()
        editor.loadContent("alpha\nbeta\ngamma\n")
        #expect(editor.line(forOffset: 0) == 1)   // "a" of alpha
        #expect(editor.line(forOffset: 5) == 1)   // the newline still ends line 1
        #expect(editor.line(forOffset: 6) == 2)   // "b" of beta
        #expect(editor.line(forOffset: 11) == 3)  // "g" of gamma
    }

    @Test("Line starts round-trip through offsets")
    func roundTrip() {
        let editor = makeEditor()
        editor.loadContent("alpha\nbeta\ngamma\ndelta")
        for line in 1...4 {
            #expect(editor.line(forOffset: editor.offset(forLine: line)) == line)
        }
    }

    @Test("An empty document is one line")
    func emptyDocument() {
        let editor = makeEditor()
        editor.loadContent("")
        #expect(editor.line(forOffset: 0) == 1)
        #expect(editor.offset(forLine: 1) == 0)
    }

    @Test("A trailing newline opens a final empty line")
    func trailingNewline() {
        let editor = makeEditor()
        editor.loadContent("alpha\n")
        // The caret after the newline sits on line 2, which starts at the end.
        #expect(editor.line(forOffset: 6) == 2)
        #expect(editor.offset(forLine: 2) == 6)
    }

    @Test("A document with no trailing newline ends on its last line")
    func noTrailingNewline() {
        let editor = makeEditor()
        editor.loadContent("alpha\nbeta")
        #expect(editor.line(forOffset: 10) == 2)
        #expect(editor.offset(forLine: 2) == 6)
    }

    @Test("Out-of-range offsets and lines clamp to the document")
    func clamping() {
        let editor = makeEditor()
        editor.loadContent("alpha\nbeta")
        #expect(editor.line(forOffset: -5) == 1)
        #expect(editor.line(forOffset: 9_999) == 2)   // past the end → last line
        #expect(editor.offset(forLine: 0) == 0)
        #expect(editor.offset(forLine: 9_999) == 6)   // past the end → last start
    }

    @Test("Editing the source invalidates the cached line starts")
    func cacheInvalidates() {
        let editor = makeEditor()
        editor.loadContent("alpha\nbeta\n")
        #expect(editor.line(forOffset: 6) == 2)       // populates the cache
        editor.loadContent("one\ntwo\nthree\nfour\n")
        #expect(editor.line(forOffset: 6) == 2)
        #expect(editor.line(forOffset: 14) == 4)      // would be 2 on a stale table
        #expect(editor.lineStarts == [0, 4, 8, 14, 19])
    }

    @Test("The default placement reserves nothing")
    func besideContentInstallsNoRuler() {
        // Numbers beside the text live in the column's own margin, drawn on the
        // background pass — so no ruler, and the text view keeps its full width.
        let editor = makeEditor()
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        scrollView.documentView = editor
        editor.showLineNumbers = true
        #expect(editor.lineNumberRuler == nil)
        #expect(!scrollView.rulersVisible)
    }

    @Test("The window-edge sub-setting installs and removes the gutter")
    func gutterInstallRemove() {
        // What the Settings toggles drive. The editor configures itself before
        // Document adds it to a scroll view, so the install has to survive
        // being asked for while there is no scroll view yet.
        let editor = makeEditor()
        editor.showLineNumbers = true
        editor.lineNumbersByWindowEdge = true
        #expect(editor.lineNumberRuler == nil)   // nothing to install onto

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        scrollView.documentView = editor         // → viewDidMoveToSuperview
        #expect(editor.lineNumberRuler != nil)
        #expect(scrollView.verticalRulerView === editor.lineNumberRuler)
        #expect(scrollView.rulersVisible)

        // Back to the default placement: the gutter goes, the numbers stay on.
        editor.lineNumbersByWindowEdge = false
        #expect(editor.lineNumberRuler == nil)
        #expect(!scrollView.rulersVisible)
        #expect(editor.showLineNumbers)

        // And turning the numbers off entirely with the gutter armed keeps it off.
        editor.lineNumbersByWindowEdge = true
        editor.showLineNumbers = false
        #expect(editor.lineNumberRuler == nil)
        #expect(!scrollView.rulersVisible)
    }

    @Test("The caret's line is inked as body text")
    func caretLineInk() {
        let editor = makeEditor()
        editor.loadContent("alpha\nbeta\ngamma\n")
        editor.setSelectedRange(NSRange(location: 7, length: 0))   // inside "beta"

        let style = editor.lineNumberStyle
        #expect(style.selectedLines == [2...2])
        #expect(style.attributed(2)[.foregroundColor] as? NSColor == editor.foregroundColor)
        #expect(style.attributed(3)[.foregroundColor] as? NSColor == editor.lineNumberColor)
        // The numbers sit below the syntax dim tier, not in it.
        #expect(editor.lineNumberColor != editor.syntaxDimColor)
    }

    @Test("Every line the selection touches is inked as body text")
    func selectedLinesInk() {
        let editor = makeEditor()
        editor.loadContent("alpha\nbeta\ngamma\ndelta\n")
        // From inside "alpha" through inside "gamma": lines 1-3.
        editor.setSelectedRange(NSRange(location: 2, length: 12))

        let style = editor.lineNumberStyle
        #expect(style.selectedLines == [1...3])
        for line in 1...3 {
            #expect(style.attributed(line)[.foregroundColor] as? NSColor
                    == editor.foregroundColor)
        }
        #expect(style.attributed(4)[.foregroundColor] as? NSColor == editor.lineNumberColor)
    }

    @Test("A selection ending at a line start doesn't claim that line")
    func selectionStopsAtLineStart() {
        let editor = makeEditor()
        editor.loadContent("alpha\nbeta\ngamma\n")
        // "alpha\n" exactly — line 2 is untouched, even though the upper bound
        // is line 2's first offset.
        editor.setSelectedRange(NSRange(location: 0, length: 6))
        #expect(editor.lineNumberStyle.selectedLines == [1...1])
    }

    @Test("The reading column keeps the whole cap; the numbers give way")
    func columnStretchesOverNumbers() {
        // The margin is never reserved for the numbers — at a cap wide enough to
        // collapse it, the column still stretches and the numbers step aside.
        let editor = makeEditor()
        editor.loadContent((1...1200).map { "line \($0)" }.joined(separator: "\n"))
        editor.maxContentWidthPoints = .greatestFiniteMagnitude
        editor.showLineNumbers = true
        editor.updateContentInset()

        #expect(editor.textContainerInset.width == EditorTextView.contentBaseInset)
        #expect(editor.lineNumbersRequiredInset > editor.textContainerInset.width)
    }

    @Test("The line-number face has tabular figures")
    func tabularFigures() {
        // The whole right-alignment scheme rests on this: Avenir Next Condensed
        // is proportional for letters but every *digit* carries the same advance,
        // so a label's width is its length times one measured digit. If the face
        // is ever swapped for a proportional-figure one, this is what catches it.
        let font = EditorTextView.lineNumberFont(ofSize: 14)
        let widths = Set((0...9).map {
            ("\($0)" as NSString).size(withAttributes: [.font: font]).width
        })
        #expect(widths.count == 1)
        // And it really is the condensed face, not the fallback.
        #expect(font.fontName == "AvenirNextCondensed-Regular")
    }

    @Test("The gutter never narrows below three digits")
    func gutterFloor() {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let floor = LineNumberRulerView.thickness(digits: 3, font: font)
        #expect(LineNumberRulerView.thickness(digits: 1, font: font) == floor)
        #expect(LineNumberRulerView.thickness(digits: 2, font: font) == floor)
    }

    @Test("The gutter widens once the line count needs a fourth digit")
    func gutterWidens() {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        #expect(LineNumberRulerView.digitCount(1) == 1)
        #expect(LineNumberRulerView.digitCount(999) == 3)
        #expect(LineNumberRulerView.digitCount(1000) == 4)
        #expect(LineNumberRulerView.thickness(digits: 4, font: font)
                > LineNumberRulerView.thickness(digits: 3, font: font))
    }
}
