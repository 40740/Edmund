import AppKit

/// Implemented by the app-side find controller (edmd's FindController). The
/// editor forwards menu/keyboard find commands here so EdmundCore stays
/// unaware of the concrete controller — same decoupling as
/// `contextFontMenuProvider`.
@MainActor public protocol EditorFindHandling: AnyObject {
    func editorShowFind(replace: Bool)
    func editorFindNext()
    func editorFindPrevious()
    func editorHideFind()
}

extension EditorTextView {

    // MARK: - Match state

    /// Replaces the current match set and requests a redraw. Draw-only — never
    /// touches storage or the selection, so it can't perturb the edit/recompose
    /// pipeline or the storage == rawSource invariant.
    public func setFindMatches(_ matches: [NSRange], current: Int?) {
        findMatches = matches
        currentMatchIndex = current
        findActive = true
        needsDisplay = true
    }

    /// Clears find highlighting (bar closed).
    public func clearFindMatches() {
        guard findActive || !findMatches.isEmpty else { return }
        findMatches = []
        currentMatchIndex = nil
        findActive = false
        needsDisplay = true
    }

    /// Reveals the match at `index` without moving the caret (a selection change
    /// would trigger the active-block-renders-raw recompose). Already-visible
    /// matches don't move the viewport; otherwise the match's line goes to the
    /// top, so a document jump lands the hit predictably rather than at an edge.
    public func revealFindMatch(_ index: Int) {
        guard findMatches.indices.contains(index) else { return }
        let range = findMatches[index]
        let origin = enclosingScrollView?.contentView.bounds.origin ?? .zero
        if !rangeIsVisible(range, forViewportOrigin: origin) {
            scrollCharacterToTop(range.location)
        }
    }

    // MARK: - Highlight drawing

    /// Paints the match highlights behind the glyphs, using the system find
    /// colour. Runs on the normal background-draw pass (so scrolling repaints
    /// exposed matches for free) and is bounded to matches intersecting the
    /// laid-out viewport, so a document with many scattered hits doesn't force
    /// whole-document layout on every frame.
    public override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard findActive, !findMatches.isEmpty, let tlm = textLayoutManager else { return }

        let visible = viewportCharRange(tlm)
        let current = NSColor.findHighlightColor
        // Non-current matches are dimmer, and dimmer still in light mode where
        // the yellow reads stronger against the white page.
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let other = current.withAlphaComponent(dark ? 0.55 : 0.3)
        // Layout-fragment frames are in text-container space; the view offsets
        // them by textContainerOrigin (which also carries the content-width
        // centering). Translate to draw in view coordinates.
        let origin = textContainerOrigin

        for (i, match) in findMatches.enumerated() {
            if let visible, NSIntersectionRange(visible, match).length == 0 { continue }
            guard let tr = blockTextRange(match, tlm) else { continue }
            (i == currentMatchIndex ? current : other).setFill()
            tlm.enumerateTextSegments(in: tr, type: .highlight, options: []) { _, frame, _, _ in
                let r = frame.offsetBy(dx: origin.x, dy: origin.y)
                if r.intersects(rect) { r.fill() }
                return true
            }
        }
    }

    /// The character range currently laid out in the viewport, or nil if
    /// unavailable (fall back to enumerating all matches).
    private func viewportCharRange(_ tlm: NSTextLayoutManager) -> NSRange? {
        guard let vp = tlm.textViewportLayoutController.viewportRange else { return nil }
        let docStart = tlm.documentRange.location
        let lo = tlm.offset(from: docStart, to: vp.location)
        let hi = tlm.offset(from: docStart, to: vp.endLocation)
        guard lo >= 0, hi >= lo else { return nil }
        return NSRange(location: lo, length: hi - lo)
    }

    // MARK: - Menu / keyboard actions
    // Only implemented here, so in Reading mode (webview is first responder)
    // these gray out automatically — no explicit validation needed.

    @objc public func showFindBar(_ sender: Any?)      { findHandler?.editorShowFind(replace: false) }
    @objc public func showFindReplaceBar(_ sender: Any?) { findHandler?.editorShowFind(replace: true) }
    @objc public func findNext(_ sender: Any?)         { findHandler?.editorFindNext() }
    @objc public func findPrevious(_ sender: Any?)     { findHandler?.editorFindPrevious() }
    @objc public func hideFindBar(_ sender: Any?)      { findHandler?.editorHideFind() }
}
