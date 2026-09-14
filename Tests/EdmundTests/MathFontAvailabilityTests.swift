import AppKit
import Foundation
import Testing

@testable import EdmundRender

/// The math engine must never trap, and must never silently pretend to have
/// typeset something it couldn't.
///
/// Both halves matter. The crash this suite guards against (issue #12) was
/// `MTFont.fontBundle`'s force-unwrapped `Bundle.module` lookup firing on the
/// main thread the first time a document with `$…$` was styled; the failure
/// mode *after* a naive fix was worse — equations quietly degrading to flat
/// Unicode with nothing saying so. These tests pin both: availability is
/// reported honestly, and the fallback is a real, legible result.
@Suite("Math — engine availability and fallback")
struct MathFontAvailabilityTests {

    @Test("Availability is a plain Bool, never a trap")
    func availabilityIsSafeToAsk() {
        // Reading this used to be unsafe: it reached SwiftMath's bundle accessor,
        // which force-unwraps and therefore kills the process when the fonts
        // aren't where it looks. `MathFonts` resolves the directory without
        // `Bundle.module`, so the question is always answerable.
        let available = MathFonts.isAvailable
        #expect(available == (MathFonts.directory != nil),
                "isAvailable and directory must agree — one is derived from the other")
    }

    @Test("A directory named like the bundle but holding no fonts does not count")
    func fontlessBundleIsNotAvailable() throws {
        // The trap's shape: a directory called `mathFonts.bundle` that has an
        // Info.plist but no fonts is exactly what `Bundle.module` returns happily
        // and SwiftMath then force-unwraps a font out of. Presence of the name
        // must not read as availability.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mathfont-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        #expect(!MathFonts.hasFont(named: MathFonts.defaultFontName, in: tmp),
                "an empty directory is not a font bundle")
    }

    @Test("The nested .copy layout SwiftMath actually ships is found")
    func nestedLayoutIsFound() throws {
        // `.copy("mathFonts.bundle")` reproduces that directory verbatim, so the
        // real path is SwiftMath_SwiftMath.bundle/mathFonts.bundle/*.otf — one
        // level deeper than the bundle name suggests. Only probing the bundle's
        // own root reports "no fonts" for a release that has every one of them,
        // and the only symptom is maths silently degrading.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mathfont-\(UUID().uuidString)")
        let nested = tmp.appendingPathComponent("mathFonts.bundle")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let font = nested.appendingPathComponent("\(MathFonts.defaultFontName).otf")
        try Data("not a real font, but a real file".utf8).write(to: font)

        #expect(MathFonts.hasFont(named: MathFonts.defaultFontName, in: tmp),
                "the nested .copy layout must be probed")
    }

    @Test("The flat resource-bundle layout is found too")
    func flatLayoutIsFound() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mathfont-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try Data("x".utf8).write(
            to: tmp.appendingPathComponent("\(MathFonts.defaultFontName).otf"))
        #expect(MathFonts.hasFont(named: MathFonts.defaultFontName, in: tmp),
                "SwiftPM's .copy lays the payload out flat")
    }

    @Test("Every engine in the chain either renders or says why it can't")
    @MainActor func chainIsTotal() {
        // The chain must not have a gap: whichever engine is `active`, the
        // coordinator answers with something drawable for non-empty input, or
        // `nil` — never a trap.
        let rendered = MathRendering.shared.render(
            latex: "x^2 + y^2 = z^2", displayMode: false,
            pointSize: 14, color: .textColor)
        #expect(rendered != nil, "a valid equation always renders, on any install")
        if let rendered {
            #expect(rendered.image.size.width > 0)
            #expect(rendered.image.size.height > 0)
            #expect(abs((rendered.ascent + rendered.descent) - rendered.image.size.height) < 0.5,
                    "ascent + descent must account for the whole image")
        }
    }

    @Test("The approximation never renders nothing for non-empty input")
    @MainActor func approximationIsAlwaysDrawable() {
        let unicode = UnicodeMathRenderer()
        for latex in ["x", "x^2", "\\frac{a}{b}", "\\alpha + \\beta", "\\frac{", "$$"] {
            let rendered = unicode.render(latex: latex, displayMode: false,
                                          pointSize: 14, color: .textColor)
            #expect(rendered != nil, "\(latex) must produce a drawable image, never a hole")
        }
    }

    @Test("Flattening is readable, not raw LaTeX")
    @MainActor func flatteningIsReadable() {
        #expect(UnicodeMathRenderer.flatten("x^2") == "x²")
        #expect(UnicodeMathRenderer.flatten("\\alpha") == "α")
        #expect(UnicodeMathRenderer.flatten("a_1") == "a₁")
        #expect(UnicodeMathRenderer.flatten("\\frac{a}{b}").contains("a"))
        #expect(UnicodeMathRenderer.flatten("\\frac{a}{b}").contains("b"))
    }

    @Test("Degraded state is reported by the coordinator, not inferred by callers")
    @MainActor func degradedStateIsReported() {
        // `isDegraded` is the one place that decides whether maths is being
        // *approximated* rather than typeset, so a missing font bundle surfaces
        // as a status line instead of per-equation guesswork.
        #expect(MathRendering.shared.isDegraded == !MathFonts.isAvailable)
    }

    @Test("A non-RGB color is a cache key, not an exception")
    func nonRGBColorDoesNotRaise() {
        // `NSColor.redComponent` raises (an Objective-C exception, which Swift
        // cannot catch) for a color in a non-RGB colorspace, and `.black` is the
        // gray profile. The renderer's cache key used to read the components
        // directly, so handing it `.black` took the process down — a latent trap
        // the editor happened to never reach, because it resolves colors to
        // device RGB before rendering.
        let blackKey = MathRendererSupport.cacheKeyColor(NSColor.black)
        let whiteKey = MathRendererSupport.cacheKeyColor(NSColor.white)
        #expect(!blackKey.isEmpty, "a gray-profile color still yields a key")
        #expect(blackKey == MathRendererSupport.cacheKeyColor(NSColor.black),
                "the key is stable for the same color")
        #expect(blackKey != whiteKey, "different colors get different keys")
    }

    @Test("Rendering with a gray-profile color works end to end")
    @MainActor func grayProfileColorRenders() {
        let rendered = MathRendering.shared.render(
            latex: "x^2", displayMode: false, pointSize: 14, color: .black)
        #expect(rendered != nil, "a legitimate color must not crash the renderer")
    }
}
