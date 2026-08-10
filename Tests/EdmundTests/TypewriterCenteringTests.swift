import Testing
import AppKit
@testable import EdmundCore

/// Typewriter mode keeps the caret at the vertical center of the viewport.
/// The failure mode this guards against: centering measured the caret from a
/// TextKit 2 height estimate (fragments above the caret not laid out), so the
/// caret landed off-center — consistently low in the bug report. Centering now
/// lays out the bounded viewport↔caret span first; these tests pin that the
/// caret ends within a couple points of center, including after scrolling away.
@Suite("Typewriter centering")
struct TypewriterCenteringTests {

    @MainActor
    private func makeWindowed() -> (EditorTextView, NSScrollView) {
        let editor = makeEditor()
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 320),
                           styleMask: [.titled], backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: win.contentLayoutRect)
        scroll.documentView = editor
        win.contentView = scroll
        win.makeFirstResponder(editor)
        editor.typewriterModeEnabled = true
        editor.isVerticallyResizable = true
        editor.minSize = NSSize(width: 0, height: 0)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                height: CGFloat.greatestFiniteMagnitude)
        editor.autoresizingMask = [.width]
        // Mirror Document's setup: the app's own inset, then the overscroll
        // pass. The overscroll is half the clip height, so it can't be computed
        // before the editor has an enclosing scroll view.
        editor.textContainerInset = NSSize(width: 24,
                                           height: EditorTextView.contentBaseVerticalInset)
        editor.updateContentInset()
        editor.updateScrollOverscroll()
        return (editor, scroll)
    }

    /// Caret's distance (pts) from the viewport's vertical center after centering.
    @MainActor
    private func offFromCenter(_ editor: EditorTextView, _ scroll: NSScrollView,
                               caretOffset off: Int) -> CGFloat {
        editor.setSelectedRange(NSRange(location: off, length: 0))
        // Center, settle the real (non-estimated) heights, then center again on
        // that settled layout — so the measurement isn't comparing two different
        // height estimates. (In the app the layout is already stable; the test
        // forces convergence because ensureFullLayout / inset changes here churn it.)
        editor.scrollCursorToCenter()
        ensureFullLayout(editor)
        editor.scrollCursorToCenter()
        editor.layoutSubtreeIfNeeded()
        guard let lr = editor.lineRect(forCharacterAt: off) else { return .greatestFiniteMagnitude }
        let docY = lr.midY + editor.textContainerOrigin.y
        let screenMid = docY - scroll.contentView.bounds.origin.y
        return abs(screenMid - scroll.contentView.bounds.height / 2)
    }

    @Test("Caret centers on mid-document lines")
    @MainActor func centersMidDocument() {
        let (editor, scroll) = makeWindowed()
        var doc = ""
        for i in 1...100 { doc += "Line \(i) content here for the document body.\n" }
        editor.loadContent(doc)
        ensureFullLayout(editor); editor.sizeToFit(); editor.layoutSubtreeIfNeeded()

        let ns = editor.rawSource as NSString
        for marker in ["Line 30 ", "Line 50 ", "Line 70 "] {
            let off = ns.range(of: marker).location
            let delta = offFromCenter(editor, scroll, caretOffset: off)
            #expect(delta < 4, "\(marker) off-center by \(delta)pt")
        }
    }

    @Test("Caret centers on a line scrolled out of view")
    @MainActor func centersAfterScrollingAway() {
        let (editor, scroll) = makeWindowed()
        var doc = ""
        for i in 1...100 { doc += "Line \(i) content here for the document body.\n" }
        editor.loadContent(doc)
        ensureFullLayout(editor); editor.sizeToFit(); editor.layoutSubtreeIfNeeded()

        // Scroll to the bottom so an early line is well off-screen, then center
        // on it — this is the path that read a stale estimate before the fix.
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, editor.frame.height - scroll.contentView.bounds.height)))
        scroll.reflectScrolledClipView(scroll.contentView)
        editor.layoutSubtreeIfNeeded()

        let off = (editor.rawSource as NSString).range(of: "Line 20 ").location
        let delta = offFromCenter(editor, scroll, caretOffset: off)
        #expect(delta < 4, "off-screen line off-center by \(delta)pt")
    }

    /// The document's ends. With no reserved blank space above the first line
    /// (ColaMD: documents open flush at the top), centering the first line
    /// clamps the viewport to the top — it can't scroll into a blank band that
    /// no longer exists. The last line still centers: there is content below it
    /// to give the caret room.
    @Test("Caret centering clamps at the document's ends")
    @MainActor func centersAtDocumentEnds() {
        let (editor, scroll) = makeWindowed()
        var doc = ""
        for i in 1...100 { doc += "Line \(i) content here for the document body.\n" }
        editor.loadContent(doc)
        ensureFullLayout(editor); editor.sizeToFit(); editor.layoutSubtreeIfNeeded()

        let ns = editor.rawSource as NSString

        // First line: centering wants to go above the document start, so the
        // viewport clamps to the actual scroll minimum (no negative overscroll).
        let firstOff = ns.range(of: "Line 1 ").location
        editor.setSelectedRange(NSRange(location: firstOff, length: 0))
        editor.scrollCursorToCenter()
        let minScroll = editor.clampedScrollY(-99_999)
        #expect(abs(scroll.contentView.bounds.origin.y - minScroll) < 2,
                "first line settled at \(scroll.contentView.bounds.origin.y), wanted the clamp \(minScroll)")

        // Last line: the caret still reaches the vertical center.
        let lastOff = ns.range(of: "Line 100 ").location
        let delta = offFromCenter(editor, scroll, caretOffset: lastOff)
        #expect(delta < 4, "last line off-center by \(delta)pt")
    }

    /// A document shorter than the window: the scroll range is [0, 0], so
    /// typewriter centering can't move the viewport — the document just stays
    /// at the top, with no blank band above it.
    @Test("A short document stays put at the top in typewriter mode")
    @MainActor func centersInShortDocument() {
        let (editor, scroll) = makeWindowed()
        editor.loadContent("Line 1 alpha\nLine 2 beta\nLine 3 gamma\nLine 4 delta\nLine 5 epsilon\n")
        ensureFullLayout(editor); editor.sizeToFit(); editor.layoutSubtreeIfNeeded()

        let off = (editor.rawSource as NSString).range(of: "Line 3 ").location
        editor.setSelectedRange(NSRange(location: off, length: 0))
        editor.scrollCursorToCenter()
        #expect(scroll.contentView.bounds.origin.y <= 0.5,
                "short-document viewport moved to \(scroll.contentView.bounds.origin.y)")
    }

    /// No blank space is reserved above the document's start in any mode —
    /// the first line opens flush at the top (ColaMD behavior). The bottom
    /// overscroll (scroll-past-end) still lives in the frame.
    @Test("No blank space is reserved above the first line")
    @MainActor func spaceReservedAboveStart() {
        let (editor, scroll) = makeWindowed()
        var doc = ""
        for i in 1...100 { doc += "Line \(i) content here for the document body.\n" }
        editor.loadContent(doc)
        ensureFullLayout(editor); editor.sizeToFit(); editor.layoutSubtreeIfNeeded()

        #expect(editor.clampedScrollY(-99_999) >= -0.5,
                "the scroll range must still start at 0")
        #expect(editor.overscrollTopPad < 0.5,
                "unexpected top overscroll: \(editor.overscrollTopPad)")
        #expect(editor.textContainerOrigin.y <= EditorTextView.contentBaseVerticalInset + 0.5,
                "first line starts \(editor.textContainerOrigin.y)pt down")
    }

    /// The top overscroll is zero in every mode — there is never a blank band
    /// over the opening line. The bottom overscroll stays in both.
    @Test("Top overscroll is zero in both modes")
    @MainActor func topSpaceIsModeScoped() {
        let (editor, scroll) = makeWindowed()
        editor.loadContent("Body text.\n")
        editor.updateScrollOverscroll()
        let clipH = scroll.contentView.bounds.height
        #expect(editor.overscrollTopPad < 0.5,
                "typewriter mode reserved top space: \(editor.overscrollTopPad)")

        editor.typewriterModeEnabled = false
        #expect(editor.overscrollTopPad < 0.5,
                "top overscroll leaked into normal mode: \(editor.overscrollTopPad)")
        #expect(editor.textContainerOrigin.y <= EditorTextView.contentBaseVerticalInset + 0.5,
                "text still starts \(editor.textContainerOrigin.y)pt down with the mode off")
        #expect(editor.overscrollBottomPad >= clipH / 2 - 1,
                "bottom overscroll should stay in both modes: \(editor.overscrollBottomPad)")
    }

    /// The regression that shipped in #260: the overscroll used to live in
    /// `NSScrollView.contentInsets`, and AppKit restricts hit-testing to the
    /// scroll view's frame *minus* its insets. Half a viewport at each end left
    /// a zero-height live area, so no click anywhere in the window reached the
    /// text — the caret stopped following clicks entirely.
    @Test("Every point of the window still routes clicks to the editor")
    @MainActor func windowStaysClickable() {
        let (editor, scroll) = makeWindowed()
        var doc = ""
        for i in 1...100 { doc += "Line \(i) content here for the document body.\n" }
        editor.loadContent(doc)
        ensureFullLayout(editor); editor.sizeToFit(); editor.layoutSubtreeIfNeeded()

        let h = scroll.bounds.height
        for y in [h - 5, h * 0.75, h / 2, h * 0.25, 5] {
            let hit = scroll.hitTest(NSPoint(x: scroll.bounds.midX, y: y))
            #expect(hit === editor,
                    "click at y=\(y) landed on \(hit.map { "\(type(of: $0))" } ?? "nothing"), not the editor")
        }
    }
}
