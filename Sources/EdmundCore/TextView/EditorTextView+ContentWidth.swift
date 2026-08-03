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

    /// Reserves scrolling room past the document's ends: half a viewport below
    /// the last line always (so the line being written is never pinned to the
    /// window's bottom edge), and half a viewport above the first line while
    /// typewriter scroll is on (so the opening screenful can reach center).
    ///
    /// Held in `NSScrollView.contentInsets` rather than grown into
    /// `textContainerInset` or the frame, because the clip view's own
    /// `constrainBoundsRect` honors it directly: the scroll range becomes
    /// `-top ... documentHeight + bottom - clipHeight` (measured on a flipped
    /// document view, which NSTextView is). Container geometry can't be
    /// budgeted against instead — `textContainerOrigin.y` comes back as
    /// AppKit's split of the frame-vs-container leftover, not the inset it was
    /// given, and the split differs by OS (macOS 15 returned inset 160 as
    /// origin 160; macos-14 returned 135, clamping the first line 14pt low).
    ///
    /// The find bar adds its height on top via `additionalTopInset`.
    public func updateScrollOverscroll() {
        guard let scrollView = enclosingScrollView else { return }
        let clipHeight = scrollView.contentView.bounds.height
        guard clipHeight > 0 else { return }
        let top = (typewriterModeEnabled ? clipHeight / 2 : 0) + additionalTopInset
        let bottom = clipHeight / 2
        guard abs(scrollView.contentInsets.top - top) > 0.5
                || abs(scrollView.contentInsets.bottom - bottom) > 0.5 else { return }
        // We own the insets from here on; AppKit's automatic pass sets them
        // from the window chrome and would drop both.
        scrollView.automaticallyAdjustsContentInsets = false
        // Changing the insets re-anchors the clip view against the new edge,
        // which slides the reader's position (measured: ~770pt on a scrolled
        // document when the pass first ran). The insets only change the
        // scrollable *range*, never the layout, so putting the origin back
        // where it was is exact.
        let origin = scrollView.contentView.bounds.origin
        scrollView.contentInsets = NSEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
        guard abs(scrollView.contentView.bounds.origin.y - origin.y) > 0.5 else { return }
        scrollView.contentView.scroll(to: NSPoint(x: origin.x, y: clampedScrollY(origin.y)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// `updateScrollOverscroll` on the next run-loop hop. Changing
    /// `contentInsets` re-tiles the scroll view, which must not happen from
    /// inside the layout pass `setFrameSize` runs in.
    func scheduleOverscrollUpdate() {
        guard enclosingScrollView != nil, !overscrollUpdateScheduled else { return }
        overscrollUpdateScheduled = true
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.overscrollUpdateScheduled = false
                self.updateScrollOverscroll()
            }
        }
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
        // Tracks the clip height, so it has to be rechecked on every resize —
        // but scheduled, for the same reason as the ruler below: this runs
        // inside `setFrameSize`, and contentInsets re-tile the scroll view.
        scheduleOverscrollUpdate()
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
