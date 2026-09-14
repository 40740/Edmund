import AppKit

// MARK: - MathRendering
//
// Which math engine is active right now, and the per-equation fallback chain —
// so a single unsupported equation, or a build whose fonts are unreachable,
// degrades one equation instead of blanking the document or killing the app.
// Both back-ends that draw math render through this rather than reaching for a
// renderer directly.
//
// The chain, in quality order:
//
//   alternate (RaTeX/WASM, if an extension installed one)
//     → SwiftMath (bundled, real typesetting)
//       → UnicodeMathRenderer (readable approximation, cannot fail)
//
// `alternate` is the seam the editor's extension host fills in
// (`EdmundCore/Math/RaTeX`). A preview process never sets it, so a preview
// resolves to the bundled SwiftMath engine and nothing else is loaded.
//
// The final step is new, and it is the difference between "an equation shows as
// flattened text" and "the app dies" when the fonts aren't where SwiftMath
// expects them (issue #12). `SwiftMathRenderer.isReady` is false in that case,
// so the chain simply doesn't include SwiftMath and the approximation answers —
// there is no code path that reaches `MTFont.fontBundle` with nothing behind it.

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

    /// True when LaTeX is being *approximated* rather than typeset — i.e. no
    /// engine with real math fonts is available in this process. Callers surface
    /// this once (a status line) rather than per equation.
    public var isDegraded: Bool { !swiftMath.isReady }

    /// Renders `latex`, falling back through the engines in quality order
    /// (alternate → SwiftMath → Unicode).
    ///
    /// `renderingErrors` controls what the last resort does with input no
    /// typesetter can parse. When `true` (the document renderers — HTML, the
    /// Quick Look preview, a read-mode export) an unparseable equation still
    /// renders as readable flattened LaTeX, so no document ever shows a hole.
    /// When `false` (the editor, which knows whether the cursor is inside the
    /// equation and reports errors in place) a typo returns `nil` and the caller
    /// keeps its "show the raw source, tinted red" path — otherwise `\frac{`
    /// would render as a plausible-looking equation and hide the mistake.
    ///
    /// Only the Unicode engine is subject to this: an engine with real fonts
    /// already refuses input it cannot typeset, which is the signal the caller
    /// expects either way.
    public func render(latex: String, displayMode: Bool,
                       pointSize: CGFloat, color: NSColor,
                       renderingErrors: Bool = true) -> RenderedMath? {
        // The approximation is skipped whenever it is the only engine left and
        // the caller wants errors reported — including the case where it *is*
        // `active`, because SwiftMath's fonts didn't resolve. Filtering it out of
        // `active` here rather than only in the fallback loop is what makes the
        // editor's red-source path survive a missing font bundle: without it, a
        // typo on a degraded install would render as a plausible equation while
        // the same typo on a healthy install shows the error.
        let primary = active
        if !(!renderingErrors && primary is UnicodeMathRenderer) {
            if let rendered = primary.render(latex: latex, displayMode: displayMode,
                                             pointSize: pointSize, color: color) {
                return rendered
            }
        }

        // `UnicodeMathRenderer` never returns nil for non-empty input, so this
        // terminates with a drawable result (or `nil` only for empty LaTeX, which
        // is the caller's "show the raw source" case).
        for engine in [swiftMath, unicode] where engine !== primary {
            if engine is UnicodeMathRenderer && !renderingErrors { continue }
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
