import Testing
import AppKit
@testable import EdmundCore

/// With typewriter scroll off, the document can be scrolled half a viewport
/// past its last line, so the line being written is never pinned to the bottom
/// edge of the window. (Typewriter scroll reserves that space in its own
/// container inset instead — see TypewriterCenteringTests.)
@Suite("Bottom overscroll")
struct BottomOverscrollTests {

    @MainActor
    private func makeWindowed(typewriter: Bool) -> (EditorTextView, NSScrollView) {
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
        editor.textContainerInset = NSSize(width: 24,
                                           height: EditorTextView.contentBaseVerticalInset)
        editor.typewriterModeEnabled = typewriter
        editor.updateContentInset()
        editor.updateScrollOverscroll()
        var doc = ""
        for i in 1...100 { doc += "Line \(i) content here for the document body.\n" }
        editor.loadContent(doc)
        ensureFullLayout(editor); editor.sizeToFit(); editor.layoutSubtreeIfNeeded()
        return (editor, scroll)
    }

    /// The clip view must accept a scroll position half a viewport past where
    /// the last line alone would allow.
    @Test("Scrolls half a viewport past the last line")
    @MainActor func overscrollsPastEnd() {
        let (editor, scroll) = makeWindowed(typewriter: false)
        let clipHeight = scroll.contentView.bounds.height
        let withoutOverscroll = max(0, editor.frame.height - clipHeight)
        let maxY = editor.clampedScrollY(99_999)
        #expect(maxY >= withoutOverscroll + clipHeight / 2 - 1,
                "scroll stops at \(maxY), document alone allows \(withoutOverscroll)")
    }

    /// Re-running the pass must not accumulate — it sets an absolute inset
    /// rather than adding to the current one.
    @Test("Re-running the overscroll pass doesn't compound it")
    @MainActor func idempotent() {
        let (editor, scroll) = makeWindowed(typewriter: false)
        let first = scroll.contentInsets.bottom
        editor.updateScrollOverscroll()
        editor.updateScrollOverscroll()
        #expect(abs(scroll.contentInsets.bottom - first) < 1,
                "bottom inset grew from \(first) to \(scroll.contentInsets.bottom)")
    }

    /// The bottom room is wanted in both modes — typewriter scroll needs it to
    /// center the last line, plain scrolling to write past the end.
    @Test("Bottom room is reserved in typewriter mode too")
    @MainActor func alsoInTypewriterMode() {
        let (_, scroll) = makeWindowed(typewriter: true)
        let clipHeight = scroll.contentView.bounds.height
        #expect(scroll.contentInsets.bottom >= clipHeight / 2 - 1,
                "bottom overscroll missing in typewriter mode: \(scroll.contentInsets.bottom)")
    }
}
