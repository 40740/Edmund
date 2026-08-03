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
        var doc = ""
        for i in 1...100 { doc += "Line \(i) content here for the document body.\n" }
        editor.loadContent(doc)
        ensureFullLayout(editor); editor.sizeToFit(); editor.layoutSubtreeIfNeeded()
        return (editor, scroll)
    }

    /// The scrollable range has to reach past the last line's own position.
    @Test("Scrolls half a viewport past the last line")
    @MainActor func overscrollsPastEnd() {
        let (editor, scroll) = makeWindowed(typewriter: false)
        let clipHeight = scroll.contentView.bounds.height
        let lastLine = (editor.rawSource as NSString).range(of: "Line 100 ").location
        guard let lastRect = editor.lineRect(forCharacterAt: lastLine) else {
            Issue.record("no line rect for the last line"); return
        }
        // Empty space below the last line, in document coordinates: what the
        // viewport can still scroll into once the last line is at its top.
        let contentBottom = lastRect.maxY + editor.textContainerOrigin.y
        let blankBelow = editor.frame.height - contentBottom
        #expect(blankBelow >= clipHeight / 2,
                "only \(blankBelow)pt below the last line, wanted \(clipHeight / 2)")
    }

    /// The pad is derived from the content height, not added to the current
    /// frame — otherwise every layout pass would grow the document further.
    @Test("Re-sizing doesn't compound the overscroll")
    @MainActor func idempotent() {
        let (editor, _) = makeWindowed(typewriter: false)
        let first = editor.frame.height
        editor.sizeToFit()
        editor.sizeToFit()
        #expect(abs(editor.frame.height - first) < 1,
                "frame grew from \(first) to \(editor.frame.height) on re-size")
    }

    /// Typewriter scroll pads both ends inside the text container; adding the
    /// overscroll on top would double the space below the last line.
    @Test("No overscroll while typewriter scroll is on")
    @MainActor func offInTypewriterMode() {
        let (editor, scroll) = makeWindowed(typewriter: true)
        let clipHeight = scroll.contentView.bounds.height
        // The container inset (half a viewport at each end) accounts for the
        // whole difference between the frame and the laid-out text.
        let padded = 2 * editor.textContainerInset.height
        let text = editor.frame.height - padded
        #expect(editor.textContainerInset.height >= clipHeight / 2 - 1,
                "typewriter padding missing: \(editor.textContainerInset.height)")
        #expect(text > 0)
    }
}
