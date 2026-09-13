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
    /// A non-default engine, once one is enabled and installed (e.g. RaTeX).
    /// `nil` until an extension provides one.
    public var alternate: MathRenderer?

    private init() {}

    /// The engine that should render right now: `alternate` if set and ready,
    /// else the always-available SwiftMath default.
    public var active: MathRenderer {
        (alternate?.isReady == true) ? alternate! : swiftMath
    }

    public func render(latex: String, displayMode: Bool,
                       pointSize: CGFloat, color: NSColor) -> RenderedMath? {
        let primary = active
        if let rendered = primary.render(latex: latex, displayMode: displayMode,
                                         pointSize: pointSize, color: color) {
            return rendered
        }
        guard primary !== swiftMath else { return nil }
        return swiftMath.render(latex: latex, displayMode: displayMode,
                                pointSize: pointSize, color: color)
    }

    /// Call after switching the active engine (or finishing an install) so
    /// on-screen equations re-render with the new engine.
    public func engineDidChange() {
        NotificationCenter.default.post(name: .mathEngineChanged, object: nil)
    }
}
