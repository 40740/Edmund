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

    @Test("Toggling the setting installs and removes the gutter")
    func gutterInstallRemove() {
        // What the Settings toggle drives. The editor configures itself before
        // Document adds it to a scroll view, so the install has to survive
        // being asked for while there is no scroll view yet.
        let editor = makeEditor()
        editor.showLineNumbers = true
        #expect(editor.lineNumberRuler == nil)   // nothing to install onto

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        scrollView.documentView = editor         // → viewDidMoveToSuperview
        #expect(editor.lineNumberRuler != nil)
        #expect(scrollView.verticalRulerView === editor.lineNumberRuler)
        #expect(scrollView.rulersVisible)

        editor.showLineNumbers = false
        #expect(editor.lineNumberRuler == nil)
        #expect(!scrollView.rulersVisible)
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
