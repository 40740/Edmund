import AppKit
import SwiftMath

// MARK: - Math rendering engines
//
// A pluggable math-typesetting engine. `SwiftMathRenderer` wraps the bundled,
// always-available SwiftMath renderer; `MathRendering` (in
// `MathRendering.swift`) coordinates which one is active. Every back-end that
// draws math renders through these — the editor's fragments and `DocumentHTML`'s
// HTML — so neither knows what engine drew it.
//
// This lives in `EdmundRender`, not `EdmundCore`, because the HTML pipeline
// needs it: turning a `$$…$$` into an inlined PNG is rendering, not editing. The
// RaTeX (WASM) engine, its installer and the extension host stay in the editor,
// and a preview process never loads them.

/// One rendered equation, tinted to the requested color: the image plus the
/// typographic ascent/descent needed to sit it on the surrounding text's
/// baseline (inline math) or split its reserved space correctly (display math).
/// `ascent + descent == image.size.height`.
public struct RenderedMath {
    public let image: NSImage
    /// Height above the baseline.
    public let ascent: CGFloat
    /// Height below the baseline (>= 0).
    public let descent: CGFloat
    public var size: CGSize { image.size }

    public init(image: NSImage, ascent: CGFloat, descent: CGFloat) {
        self.image = image
        self.ascent = ascent
        self.descent = descent
    }
}

/// A math-typesetting engine. Renders LaTeX to an image plus the metrics
/// needed to place it against surrounding text. `@MainActor` because
/// rendering touches AppKit drawing (SwiftMath's `MTMathImage`, `NSImage`).
@MainActor
public protocol MathRenderer: AnyObject {
    /// Stable identity, distinguishing engines (e.g. "swiftmath").
    var id: String { get }
    /// Whether this renderer can render right now (loaded, no pending
    /// download/install).
    var isReady: Bool { get }
    /// Renders `latex`; `displayMode` selects block vs inline typesetting.
    /// Returns `nil` when the engine can't render it (unknown command, parse
    /// error, not ready) so the caller can fall back to another engine or
    /// show the raw source.
    func render(latex: String, displayMode: Bool,
               pointSize: CGFloat, color: NSColor) -> RenderedMath?
}

/// Wraps SwiftMath — bundled, native, always ready. The default (and, today,
/// only) renderer. Folds together the render+metrics logic that used to be
/// duplicated between `EditorTextView.mathOverlay` (edit mode) and
/// `DocumentHTML.fillMath`'s private `mathImage` (read mode), so both
/// back-ends share one implementation.
@MainActor
public final class SwiftMathRenderer: MathRenderer {
    public let id = "swiftmath"

    /// Whether the fonts this engine needs are reachable in this process.
    ///
    /// This is *not* a guard, and it is not what makes rendering safe: SwiftMath
    /// resolves its fonts through `Bundle.module`, which traps rather than
    /// returning `nil`, and `MTMathImage` acquires its font in a stored-property
    /// default — i.e. its initialiser is itself a crash site (issue #12, still
    /// present in 5.28.0, where the guard sat *after* it). `isReady` reports that
    /// the fonts were acquired at startup (see `MathFonts.prepare()`), which is
    /// the fact that makes the rest of this file's SwiftMath calls safe.
    public var isReady: Bool { MathFonts.isAvailable }

    private final class Cached {
        let image: NSImage
        let ascent: CGFloat
        let descent: CGFloat
        init(image: NSImage, ascent: CGFloat, descent: CGFloat) {
            self.image = image
            self.ascent = ascent
            self.descent = descent
        }
    }

    /// Rendered math is cached so repeated renders of the same equation (a
    /// keystroke restyle, or the same equation appearing more than once in a
    /// read-mode export) don't re-typeset. The key encodes everything that
    /// affects the pixels/metrics: latex, display vs inline, font size, and
    /// the resolved color.
    // NSCache is internally thread-safe; `nonisolated(unsafe)` opts it out of
    // the Swift 6 Sendable check (in practice it's only touched on the main actor).
    nonisolated(unsafe) private let cache = NSCache<NSString, Cached>()

    public init() {}

    public func render(latex: String, displayMode: Bool,
                       pointSize: CGFloat, color: NSColor) -> RenderedMath? {
        let key = "\(displayMode ? "D" : "I")|\(String(format: "%.1f", pointSize))|" +
                  "\(String(format: "%.3f,%.3f,%.3f,%.3f", color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent))|" +
                  latex as NSString

        if let cached = cache.object(forKey: key) {
            return RenderedMath(image: cached.image, ascent: cached.ascent, descent: cached.descent)
        }

        // The fonts were acquired before any of this could run (see
        // `MathFonts.prepare()`), so the remaining calls into SwiftMath land on
        // a bundle it can find. Unreachable fonts degrade the equation instead
        // of the process.
        guard MathFonts.prepare(), let font = MathFonts.font else { return nil }

        let mode: MTMathUILabelMode = displayMode ? .display : .text
        let math = MTMathImage(latex: latex, fontSize: pointSize, textColor: color, labelMode: mode)
        // Hand it the resolved font: `MTMathImage.font` is a stored default that
        // would otherwise be built by `Bundle.module`, inside this initialiser —
        // the trap 5.29.0 exists to get out of the way of. Setting it to the font
        // created at startup means the lookup never happens here.
        math.font = font
        // SwiftMath sizes the image to the exact typographic ascent+descent,
        // which crops a glyph's ink overshoot below the baseline — the bottom
        // of a lone `x`/`c` sits flush on the image edge and renders clipped.
        // A small content inset gives the rasterizer room so the full glyph is
        // drawn; it's folded into ascent/descent below so alignment is unchanged.
        let insetPad: CGFloat = 2
        math.contentInsets = MTEdgeInsets(top: insetPad, left: 0, bottom: insetPad, right: 0)
        let (error, image) = math.asImage()
        guard error == nil, let image else { return nil }

        // The baseline's distance from the image bottom, derived the way
        // SwiftMath's own `asImage()` derives its `textY`: the display list's
        // ascent/descent with its `height < fontSize/2` clamp (which re-centers
        // small glyphs — a lone x/c/n — and is why ignoring it left those a pixel
        // low), plus the inset we added.
        //
        // Read off the *shared panel* — the one font this process ever builds,
        // created while the fonts were known to be in place — rather than off a
        // fresh `MTMathUILabel`: another label means another font lookup, and a
        // font lookup in the render path is what the acquisition order exists to
        // avoid. `MTMathImage` keeps its display list private, so the panel is
        // what can be asked.
        let panel = MathFonts.panel(latex: latex, mode: mode, size: pointSize)
        let asc = panel?.displayList?.ascent ?? 0
        let desc = panel?.displayList?.descent ?? 0
        let clamped = max(asc + desc, pointSize / 2)
        let descent = (asc + desc - clamped) / 2 + desc + insetPad
        let ascent = image.size.height - descent

        cache.setObject(Cached(image: image, ascent: ascent, descent: descent), forKey: key)
        return RenderedMath(image: image, ascent: ascent, descent: descent)
    }
}
