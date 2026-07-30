import AppKit
import CoreText

// MARK: - RaTeX DisplayList → NSImage
//
// RaTeX's WASM (`renderLatex`) returns a "display list" JSON — the same
// intermediate every RaTeX binding consumes (docs/DISPLAYLIST_JSON_PROTOCOL.md).
// It does NOT contain rasterized pixels or glyph outlines; it references glyphs
// by font name + Unicode code point, plus rule lines. We rasterize it ourselves
// with CoreText + the KaTeX fonts, which keeps the shipped app Swift-only (the
// WASM is sandboxed data) and gives us the exact ascent/descent the overlay
// model needs — no dependency on RaTeX's own renderer or a DOM/canvas.
//
// Coordinates are in em (multiply by point size). The box origin is top-left,
// y increases downward; a glyph's `y` is its baseline. `height` is the ascent
// (baseline sits at y = height) and `depth` is the descent.

/// Decoded RaTeX display list. Only the fields we render are modeled; unknown
/// item types decode to `.unknown` and are skipped.
struct RaTeXDisplayList: Decodable {
    let width: Double
    let height: Double   // ascent (em); baseline at y = height
    let depth: Double    // descent (em)
    let items: [Item]

    struct RGBA: Decodable { let r, g, b, a: Double }

    enum Item: Decodable {
        case glyph(font: String, charCode: Int, x: Double, y: Double, scale: Double, color: RGBA)
        case line(x: Double, y: Double, width: Double, thickness: Double, color: RGBA)
        case unknown

        private enum Keys: String, CodingKey {
            case type, font, char_code, x, y, scale, color, width, thickness
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            switch try c.decode(String.self, forKey: .type) {
            case "GlyphPath":
                self = .glyph(font: try c.decode(String.self, forKey: .font),
                              charCode: try c.decode(Int.self, forKey: .char_code),
                              x: try c.decode(Double.self, forKey: .x),
                              y: try c.decode(Double.self, forKey: .y),
                              scale: try c.decodeIfPresent(Double.self, forKey: .scale) ?? 1,
                              color: try c.decode(RGBA.self, forKey: .color))
            case "Line":
                self = .line(x: try c.decode(Double.self, forKey: .x),
                             y: try c.decode(Double.self, forKey: .y),
                             width: try c.decode(Double.self, forKey: .width),
                             thickness: try c.decode(Double.self, forKey: .thickness),
                             color: try c.decode(RGBA.self, forKey: .color))
            default:
                self = .unknown
            }
        }
    }
}

/// Rasterizes a RaTeX display list to an `NSImage` + baseline metrics. The KaTeX
/// fonts are supplied by an injected loader (production loads them from the
/// installed extension directory; tests point it at a fixture directory).
@MainActor
final class RaTeXDisplayListRenderer {
    /// Maps a RaTeX font name ("Math-Italic") to a `CGFont`, or nil if missing.
    private let fontLoader: (String) -> CGFont?
    /// Extra pixels of transparent inset so a glyph's ink overshoot isn't
    /// clipped at the image edge (mirrors the SwiftMath path's inset).
    private let insetPad: CGFloat = 2

    init(fontLoader: @escaping (String) -> CGFont?) {
        self.fontLoader = fontLoader
    }

    /// Renders `json` (a RaTeX display list) at `pointSize`, tinting every item
    /// to `color` (so the render cache can stay keyed by color for light/dark).
    /// Returns nil on decode failure or empty output.
    func render(json: String, pointSize: CGFloat, color: NSColor, scale: CGFloat) -> RenderedMath? {
        guard let data = json.data(using: .utf8),
              let dl = try? JSONDecoder().decode(RaTeXDisplayList.self, from: data) else { return nil }

        let fs = pointSize
        let boxW = CGFloat(dl.width) * fs
        let boxH = CGFloat(dl.height + dl.depth) * fs
        guard boxW > 0, boxH > 0 else { return nil }

        let pxW = Int(((boxW) * scale).rounded()) + Int((insetPad * 2 * scale).rounded())
        let pxH = Int(((boxH) * scale).rounded()) + Int((insetPad * 2 * scale).rounded())
        guard let ctx = CGContext(data: nil, width: max(1, pxW), height: max(1, pxH),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        // A raw CGBitmapContext (not backed by a window/NSGraphicsContext)
        // defaults antialiasing and font smoothing OFF — unlike SwiftMath's
        // path, which renders through higher-level Cocoa APIs that don't have
        // this problem. Without these, glyphs come out visibly softer/thinner
        // than on-screen text elsewhere in the app.
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldSmoothFonts(true)
        ctx.setAllowsFontSmoothing(true)
        ctx.setShouldSubpixelPositionFonts(true)
        ctx.setAllowsFontSubpixelPositioning(true)

        // Work in a y-up context (CG default). Do NOT flip — flipping the context
        // draws glyphs upside down. Convert the display list's top-down y to y-up
        // via boxH - y. `insetPad` shifts everything in by the transparent margin.
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: insetPad, y: insetPad)
        let fill = (color.usingColorSpace(.deviceRGB) ?? color).cgColor

        for item in dl.items {
            switch item {
            case let .glyph(font, charCode, x, y, glyphScale, _):
                guard let cgFont = fontLoader(font), let scalar = UnicodeScalar(charCode) else { continue }
                let ctFont = CTFontCreateWithGraphicsFont(cgFont, fs * CGFloat(glyphScale), nil, nil)
                var utf16 = Array(String(scalar).utf16)
                var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
                guard CTFontGetGlyphsForCharacters(ctFont, &utf16, &glyphs, utf16.count),
                      glyphs[0] != 0 else { continue }
                ctx.saveGState()
                ctx.setFillColor(fill)
                var pos = CGPoint(x: CGFloat(x) * fs, y: boxH - CGFloat(y) * fs)
                CTFontDrawGlyphs(ctFont, &glyphs, &pos, 1, ctx)
                ctx.restoreGState()

            case let .line(x, y, width, thickness, _):
                ctx.setFillColor(fill)
                let th = CGFloat(thickness) * fs
                ctx.fill(CGRect(x: CGFloat(x) * fs, y: boxH - CGFloat(y) * fs - th / 2,
                                width: CGFloat(width) * fs, height: th))

            case .unknown:
                continue
            }
        }

        guard let cgImage = ctx.makeImage() else { return nil }
        // NSImage sized in points, backed by a 2x/3x rep so it stays crisp; the
        // inset is included in the point size on both axes.
        let pointSizeBox = NSSize(width: boxW + insetPad * 2, height: boxH + insetPad * 2)
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = pointSizeBox
        let image = NSImage(size: pointSizeBox)
        image.addRepresentation(rep)

        // The inset was added symmetrically; fold the bottom half into descent so
        // the baseline placement is unchanged (same trick as the SwiftMath path).
        return RenderedMath(image: image,
                            ascent: CGFloat(dl.height) * fs + insetPad,
                            descent: CGFloat(dl.depth) * fs + insetPad)
    }
}
