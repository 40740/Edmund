import AppKit

// MARK: - MathRendering
//
// Which math engine is active right now, and the per-equation fallback to the
// bundled SwiftMath renderer when a non-default one (RaTeX) can't handle a
// construct — so a single unsupported equation doesn't blank the document.
// Both back-ends that draw math render through this rather than reaching for a
// renderer directly.
//
// `alternate` is the seam the editor's extension host fills in
// (`EdmundCore/Math/RaTeX`). A preview process never sets it, so a preview
// resolves to the bundled SwiftMath engine and nothing else is loaded.

public extension Notification.Name {
    /// Posted by `MathRendering.engineDidChange()`. Editors observe this and
    /// recompose their math blocks (narrowest recompose that covers them).
    static let mathEngineChanged = Notification.Name("EdmundCore.mathEngineChanged")
}

@MainActor
public final class MathRendering {
    public static let shared = MathRendering()

    public let swiftMath = SwiftMathRenderer()
    /// Last resort: plain readable Unicode, used when no typesetting engine can
    /// run at all (SwiftMath's fonts unreachable — see `MathFonts`). Never
    /// crashes and never returns `nil` for non-empty input, so a document with
    /// `$…$` always shows something rather than a hole or a trap.
    public let unicode = UnicodeMathRenderer()
    /// A non-default engine, once one is enabled and installed (e.g. RaTeX).
    /// `nil` until an extension provides one.
    public var alternate: MathRenderer?

    private init() {}

    /// The engine that should render right now: `alternate` if set and ready,
    /// else SwiftMath if its fonts resolved, else the Unicode approximation.
    public var active: MathRenderer {
        if let alternate, alternate.isReady { return alternate }
        return swiftMath.isReady ? swiftMath : unicode
    }

    /// True when LaTeX is being approximated rather than typeset — i.e. no
    /// engine with real math fonts is available in this process. Callers surface
    /// this once (a status/banner) instead of per equation.
    public var isDegraded: Bool { !swiftMath.isReady }

    public func render(latex: String, displayMode: Bool,
                       pointSize: CGFloat, color: NSColor) -> RenderedMath? {
        let primary = active
        if let rendered = primary.render(latex: latex, displayMode: displayMode,
                                         pointSize: pointSize, color: color) {
            return rendered
        }
        // Fall back through the engines in quality order. The last one is
        // SwiftMath itself, which is skipped when its fonts didn't resolve — and
        // `UnicodeMathRenderer` never returns nil for non-empty input, so this
        // terminates with a drawable result (or `nil` only for empty LaTeX,
        // which is the caller's "show the raw source" case).
        let fallbacks: [MathRenderer] = [swiftMath, unicode]
        for engine in fallbacks where engine !== primary {
            guard engine.isReady else { continue }
            if let rendered = engine.render(latex: latex, displayMode: displayMode,
                                            pointSize: pointSize, color: color) {
                return rendered
            }
        }
        return nil
    }

    /// Call after switching the active engine (or finishing an install) so
    /// on-screen equations re-render with the new engine.
    public func engineDidChange() {
        NotificationCenter.default.post(name: .mathEngineChanged, object: nil)
    }
}
