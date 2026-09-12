import AppKit
import Foundation
import EdmundMarkdown

// MARK: - LucideIcons (AppKit)
//
// The AppKit halves of `LucideIcons`: the tinted `NSImage` the editor overlays,
// and the stroke geometry as a `CGPath`. Split out of `EdmundMarkdown` (which
// carries the geometry itself, and is what the HTML renderer and the Quick Look
// preview use) so that a process which only turns markdown into HTML doesn't
// link AppKit's image machinery.
//
// `inlineSVG` / `geometry` / `path` are used from all three modules, so they
// stay where they are defined.

extension LucideIcons {

    /// An `NSImage` of the icon stroked in `color`, sized to a `pointSize`
    /// square. Renders the SVG (in black) then tints with `.sourceIn` so the
    /// glyph matches `color` exactly regardless of the SVG decoder's color space
    /// — the same technique the PDF icon path used. `sourceIn` (not
    /// `sourceAtop`) matters when `color` is itself translucent (e.g. a dynamic
    /// system color like `.secondaryLabelColor`): `sourceIn`'s result alpha is
    /// `color.alpha * baseGlyphAlpha`, so the tint's own translucency survives;
    /// `sourceAtop` keeps only the base glyph's alpha, silently discarding the
    /// tint's alpha — invisible with the opaque theme colors this was first
    /// used with, but it flattens a translucent tint to solid opaque. `nil` for
    /// an unknown id or if the platform SVG decoder can't build the image.
    static func image(_ name: String, color: NSColor, pointSize: CGFloat) -> NSImage? {
        guard let g = geometry[name],
              let data = strokeSVG(geometry: g, stroke: "#000000").data(using: .utf8),
              let base = NSImage(data: data) else { return nil }
        base.cacheMode = .never   // re-rasterize the SVG at each draw scale (crisp on Retina)
        let box = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: box, flipped: false) { rect in
            base.draw(in: rect)
            color.setFill()
            NSGraphicsContext.current?.cgContext.setBlendMode(.sourceIn)
            rect.fill()
            return true
        }
        image.cacheMode = .never
        return image
    }

    /// The icon's stroke geometry as a CGPath in Lucide's canonical 24×24,
    /// y-down viewBox space (stroke it with width 2, round caps/joins, to
    /// match the rendered SVG). Used where the icon must be drawn as a
    /// *shape*, not an image — an image on a wrapping TextKit 2 fragment
    /// wedges its layout to one line (see FragmentOverlay). `nil` for an
    /// unknown id.
    static func path(_ name: String) -> CGPath? {
        guard let g = geometry[name] else { return nil }
        return SVGPath.path(fromGeometry: g)
    }
}
