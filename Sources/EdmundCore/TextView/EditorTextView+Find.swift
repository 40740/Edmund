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
        stopEmphasis()
        needsDisplay = true
    }

    /// Reveals the match at `index` without moving the caret (a selection change
    /// would trigger the active-block-renders-raw recompose). Already-visible
    /// matches don't move the viewport; otherwise the match's line goes to the
    /// top, so a document jump lands the hit predictably rather than at an edge.
    /// Also fires the pop animation on the freshly-focused match.
    public func revealFindMatch(_ index: Int) {
        guard findMatches.indices.contains(index) else { return }
        let range = findMatches[index]
        let origin = enclosingScrollView?.contentView.bounds.origin ?? .zero
        if !rangeIsVisible(range, forViewportOrigin: origin) {
            scrollCharacterToTop(range.location)
        }
        emphasize(range)
    }

    // MARK: - Highlight drawing

    /// Paints a grey background behind every match (CotEditor-style), plus a
    /// yellow "pop" box on the match just navigated to: a rounded rect a touch
    /// larger than the text that swells slightly and fades out. Draw-only, on the
    /// background pass (behind the glyphs, so the text stays legible through the
    /// pop) and bounded to the laid-out viewport so many scattered hits don't
    /// force whole-document layout on every frame.
    public override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard findActive, !findMatches.isEmpty, let tlm = textLayoutManager else { return }

        let visible = viewportCharRange(tlm)
        // Layout-fragment frames are in text-container space; the view offsets
        // them by textContainerOrigin (which also carries the content-width
        // centering). Translate to draw in view coordinates.
        let origin = textContainerOrigin

        // Grey resting background for every visible match.
        NSColor.unemphasizedSelectedTextBackgroundColor.setFill()
        for match in findMatches {
            if let visible, NSIntersectionRange(visible, match).length == 0 { continue }
            guard let tr = blockTextRange(match, tlm) else { continue }
            tlm.enumerateTextSegments(in: tr, type: .highlight, options: []) { _, frame, _, _ in
                let r = frame.offsetBy(dx: origin.x, dy: origin.y)
                if r.intersects(rect) { r.fill() }
                return true
            }
        }

        // Pop box over the emphasised match: holds at full yellow, then swells
        // outward and fades out. `emphasisProgress` runs 0…1 over the whole
        // duration; the first `holdFraction` of it is the steady hold.
        guard let em = emphasisRange, emphasisProgress < 1,
              let tr = blockTextRange(em, tlm) else { return }
        let holdFraction = CGFloat(Self.emphasisHold / Self.emphasisDuration)
        let fade = max(0, (emphasisProgress - holdFraction) / (1 - holdFraction))
        let grow = 2 + fade * 4                       // 2 → 6pt beyond the text box
        let alpha = 1 - fade                          // fade to transparent

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35 * alpha)   // fades with the box
        shadow.shadowOffset = NSSize(width: 0, height: -1.5)                   // flipped view: downward
        shadow.shadowBlurRadius = 4
        shadow.set()
        NSColor.findHighlightColor.withAlphaComponent(alpha).setFill()
        tlm.enumerateTextSegments(in: tr, type: .highlight, options: []) { _, frame, _, _ in
            let box = frame.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -grow, dy: -grow)
            if box.intersects(rect) {
                NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
            }
            return true
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Pop animation

    /// Full yellow is held for `emphasisHold`, then swells + fades over
    /// `emphasisFade`.
    private static let emphasisHold: CFTimeInterval = 1.0
    private static let emphasisFade: CFTimeInterval = 0.2
    private static var emphasisDuration: CFTimeInterval { emphasisHold + emphasisFade }

    /// Starts (or restarts) the pop on `range`, driven by a display link so it
    /// stays smooth without a manual timer.
    private func emphasize(_ range: NSRange) {
        emphasisLink?.invalidate()
        emphasisRange = range
        emphasisProgress = 0
        let link = displayLink(target: self, selector: #selector(stepEmphasis))
        link.add(to: .main, forMode: .common)
        emphasisLink = link
        needsDisplay = true
    }

    private func stopEmphasis() {
        emphasisLink?.invalidate()
        emphasisLink = nil
        emphasisRange = nil
        emphasisProgress = 0
    }

    @objc private func stepEmphasis(_ link: CADisplayLink) {
        // targetTimestamp - duration ≈ link start on the first tick; use the
        // link's own clock so pauses/dropped frames stay in sync.
        emphasisProgress = min(1, emphasisProgress + CGFloat(link.duration / Self.emphasisDuration))
        needsDisplay = true
        if emphasisProgress >= 1 { stopEmphasis(); needsDisplay = true }
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
