import AppKit

// MARK: - Content width (centered reading column)
//
// The text column has a physical maximum width (set in cm in Settings and
// converted to points using the display's real PPI). Windows wider than the
// cap get symmetric side margins that center the column; narrower windows
// fill edge-to-edge as usual. This is CSS `max-width` semantics: the cap is
// an absolute physical size, not a fraction of the window or the screen, so
// the column doesn't widen when you make the window bigger.

extension EditorTextView {

    /// Padding applied on each side of the text column at all window sizes.
    static let contentBaseInset: CGFloat = 24

    /// Padding above the first line and below the last one, outside typewriter
    /// scroll. `Document` seeds the text view with this value.
    public static let contentBaseVerticalInset: CGFloat = 18

    /// Grows the vertical inset to half a viewport while typewriter scroll is
    /// on, and restores the configured inset when it goes off.
    ///
    /// Typewriter scroll centers the caret by scrolling, and
    /// `centerViewportOnCaret` can only scroll within
    /// [0, frame.height - viewportHeight]. Without half a viewport of slack at
    /// each end there is nowhere to scroll to, so the first screenful, the last
    /// screenful, and any document shorter than the window never center at all.
    ///
    /// Purely additive: it remembers the inset it grew from rather than
    /// assuming a value, so turning the mode off restores exactly what was
    /// configured. Only the vertical component is touched — re-applying the
    /// column inset here would re-wrap text for no reason.
    func updateVerticalContentInset() {
        func apply(_ height: CGFloat) {
            guard abs(textContainerInset.height - height) > 0.5 else { return }
            textContainerInset = NSSize(width: textContainerInset.width, height: height)
        }
        guard typewriterModeEnabled,
              let clip = enclosingScrollView?.contentView, clip.bounds.height > 0
        else {
            if let restore = insetBeforeTypewriterPadding {
                insetBeforeTypewriterPadding = nil
                apply(restore)
            }
            return
        }
        let base = insetBeforeTypewriterPadding ?? textContainerInset.height
        insetBeforeTypewriterPadding = base
        apply(max(base, clip.bounds.height / 2))
    }

    /// The symmetric horizontal inset for a given view width and max-column width.
    /// `maxContentWidth == .greatestFiniteMagnitude` → base inset only (fills the window).
    /// When the window is too narrow to fit `maxContentWidth`, the column also fills.
    public static func horizontalInset(viewWidth: CGFloat, maxContentWidth: CGFloat) -> CGFloat {
        let available = viewWidth - 2 * contentBaseInset
        guard available > maxContentWidth else { return contentBaseInset }
        return contentBaseInset + (available - maxContentWidth) / 2
    }

    /// Recomputes the horizontal text inset from the current bounds + max-column cap,
    /// preserving the vertical inset. Usually no recompose — only the inset
    /// changes and TextKit 2 reflows wrapped text on its own. The exception is
    /// image overlays: their scaled-to-fit size is baked into the styled
    /// attribute at render time (§4 fragmentOverlay), not recomputed at draw
    /// time, so a column narrower than an already-rendered image needs those
    /// blocks restyled to shrink it.
    public func updateContentInset() {
        let target = Self.horizontalInset(viewWidth: bounds.width,
                                          maxContentWidth: maxContentWidthPoints)
        let widthChanged = abs(textContainerInset.width - target) > 0.5
        if widthChanged {
            textContainerInset = NSSize(width: target, height: textContainerInset.height)
        }
        // Tracks the clip height, so it has to be rechecked on every resize.
        updateVerticalContentInset()
        // This margin is where the line numbers live, so resizing it can push
        // them out to the window-edge gutter or bring them back beside the text.
        // Checked even when the inset held steady: the document's digit count
        // grows on its own, and this is the cheapest place that sees both.
        // Scheduled rather than applied — this runs inside `setFrameSize`, and
        // re-tiling the scroll view from inside its own layout is a crash.
        scheduleLineNumberPlacementUpdate()
        // Image overlays are sized against the column width only, so a
        // vertical-only change needs no recompose.
        guard widthChanged else { return }

        let imageBlocks = IndexSet(blocks.indices.filter { blocks[$0].content.contains("![") })
        guard !imageBlocks.isEmpty else { return }
        for idx in imageBlocks { blocks[idx].isStyled = false }
        recomposeDirty(imageBlocks, cursorInRaw: currentCursorInRaw(), settingSelection: true)
    }

    /// Recompute the centered inset as the view width changes (window resize).
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateContentInset()
    }
}
