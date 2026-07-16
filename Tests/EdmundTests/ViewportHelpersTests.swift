import Testing
import AppKit
@testable import EdmundCore

/// `line(forOffset:)` / `offset(forLine:)` are the character-offset ↔
/// 1-indexed-line conversions used to sync the read-mode viewport with the
/// editor. They must agree with swift-markdown's SourceLocation convention
/// (newline-counted, UTF-16 offsets) since callers cross-reference the two.
@Suite("Viewport line/offset helpers")
struct ViewportHelpersTests {

    @Test("Empty document is a single line")
    @MainActor func emptyDocument() {
        let editor = makeEditor()
        editor.loadContent("")
        #expect(editor.line(forOffset: 0) == 1)
        #expect(editor.offset(forLine: 1) == 0)
    }

    @Test("Single line document")
    @MainActor func singleLine() {
        let editor = makeEditor()
        editor.loadContent("hello world")
        #expect(editor.line(forOffset: 0) == 1)
        #expect(editor.line(forOffset: 5) == 1)
        #expect(editor.line(forOffset: 11) == 1)
        #expect(editor.offset(forLine: 1) == 0)
    }

    @Test("Multi-line document: offsets at newline boundaries")
    @MainActor func multiLineBoundaries() {
        let editor = makeEditor()
        // Lines:  "aa\n" (0-2, \n@2)  "bbb\n" (3-6, \n@6)  "c" (7)
        editor.loadContent("aa\nbbb\nc")
        #expect(editor.line(forOffset: 0) == 1)   // start of "aa"
        #expect(editor.line(forOffset: 2) == 1)   // the "\n" itself still counts as line 1
        #expect(editor.line(forOffset: 3) == 2)   // just past the "\n" -> start of "bbb"
        #expect(editor.line(forOffset: 6) == 2)
        #expect(editor.line(forOffset: 7) == 3)   // start of "c"
        #expect(editor.line(forOffset: 8) == 3)   // end of document

        #expect(editor.offset(forLine: 1) == 0)
        #expect(editor.offset(forLine: 2) == 3)
        #expect(editor.offset(forLine: 3) == 7)
    }

    @Test("offset(forLine:) clamps out-of-range input")
    @MainActor func clamping() {
        let editor = makeEditor()
        editor.loadContent("aa\nbbb\nc")
        #expect(editor.offset(forLine: 0) == 0)
        #expect(editor.offset(forLine: -5) == 0)
        #expect(editor.offset(forLine: 100) == 7)  // clamps to start of last line
    }

    @Test("Non-BMP character before a newline uses UTF-16 offsets")
    @MainActor func nonBMPCharacter() {
        let editor = makeEditor()
        // "a😀\nb": 'a'(1) + 😀(2 UTF-16 units) + '\n'(1) = line 1 spans [0,4);
        // line 2 ("b") starts at offset 4.
        editor.loadContent("a😀\nb")
        let ns = editor.rawSource as NSString
        #expect(ns.length == 5)
        #expect(editor.line(forOffset: 0) == 1)   // 'a'
        #expect(editor.line(forOffset: 1) == 1)   // first UTF-16 unit of the emoji
        #expect(editor.line(forOffset: 2) == 1)   // second UTF-16 unit of the emoji
        #expect(editor.line(forOffset: 3) == 1)   // the "\n"
        #expect(editor.line(forOffset: 4) == 2)   // 'b'
        #expect(editor.offset(forLine: 2) == 4)
    }
}

/// `scrollCharacterToTop` live-geometry check, mirroring the windowed setup
/// in TypewriterCenteringTests.
@Suite("scrollCharacterToTop")
struct ScrollCharacterToTopTests {

    @MainActor
    private func makeWindowed() -> (EditorTextView, NSScrollView) {
        let editor = makeEditor()
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 320),
                           styleMask: [.titled], backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: win.contentLayoutRect)
        scroll.documentView = editor
        win.contentView = scroll
        win.makeFirstResponder(editor)
        editor.isVerticallyResizable = true
        editor.minSize = NSSize(width: 0, height: 0)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                height: CGFloat.greatestFiniteMagnitude)
        editor.autoresizingMask = [.width]
        return (editor, scroll)
    }

    @Test("Scrolls the target line to the viewport top")
    @MainActor func scrollsToTop() {
        let (editor, scroll) = makeWindowed()
        var doc = ""
        for i in 1...100 { doc += "Line \(i) content here for the document body.\n" }
        editor.loadContent(doc)
        ensureFullLayout(editor); editor.sizeToFit(); editor.layoutSubtreeIfNeeded()

        let off = (editor.rawSource as NSString).range(of: "Line 50 ").location
        editor.scrollCharacterToTop(off)
        editor.layoutSubtreeIfNeeded()

        guard let lr = editor.lineRect(forCharacterAt: off) else {
            Issue.record("no line rect for target offset")
            return
        }
        let docTopY = lr.minY + editor.textContainerOrigin.y
        let screenTopY = docTopY - scroll.contentView.bounds.origin.y
        #expect(abs(screenTopY) < 4, "target line landed \(screenTopY)pt from viewport top")
    }
}
