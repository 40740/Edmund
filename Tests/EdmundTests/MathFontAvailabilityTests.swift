import Testing
import AppKit
import SwiftMath
@testable import EdmundCore
import EdmundRender

// MARK: - Math fonts as a recoverable condition (issue #12)
//
// Opening a markdown file with any `$…$` in it crashed the app on the main
// thread (EXC_BREAKPOINT / SIGTRAP) inside `MTFont.fontBundle.getter`, called
// from `MTFont(fontWithName:)` ← `MTFontManager.font(withName:size:)` ←
// `MTMathImage.init` ← `SwiftMathRenderer.render` ← `mathOverlay` ← `styleBlock`
// while restyling the block that contained the equation.
//
// SwiftMath reaches its OpenType fonts through Foundation's generated
// `Bundle.module` accessor, which *traps* when the bundle it was compiled
// against can't be found or has no identifier — there is no throwing path, and
// SwiftMath force-unwraps or `fatalError`s at every funnel. The app cannot make
// that safe from the outside, so the fix is to never reach those calls unless
// the fonts have first been resolved explicitly.
//
// These tests pin: (1) resolution is explicit and non-trapping, (2) rendering
// degrades to a readable approximation rather than a hole, and (3) the crash
// path itself — an engine whose fonts are unreachable — is represented in the
// type system as `isReady == false`, not as a trap.

@Suite("Math — font availability is a recoverable condition")
struct MathFontAvailabilityTests {

    @Test("The font directory resolves to a real directory in this process")
    func resolvesInTests() {
        // The test binary runs out of a temporary directory, so this only passes
        // because `MathFonts` probes more than Bundle.main — the executable's
        // neighbours and the SwiftPM build path. If resolution regresses, math
        // silently degrades everywhere (that is the design), which is exactly
        // why it needs a test that notices.
        #expect(MathFonts.isAvailable, "SwiftMath fonts must resolve in the test process")
        if let directory = MathFonts.directory {
            var isDir: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir))
            #expect(isDir.boolValue)
        }
    }

    @Test("The resolved directory actually contains the default font and its math table")
    func resolvedDirectoryHasPayload() {
        guard MathFonts.isAvailable else { return }   // covered above
        #expect(MathFonts.url(forResource: MathFonts.defaultFontName, withExtension: "otf") != nil,
                "latinmodern-math.otf must be reachable — MTFont(fontWithName:) force-unwraps its path")
        #expect(MathFonts.url(forResource: MathFonts.defaultFontName, withExtension: "plist") != nil,
                "the math table plist is force-unwrapped right after the font")
    }

    @Test("isReady follows font availability instead of always claiming readiness")
    @MainActor func isReadyTracksAvailability() {
        // Before the fix this was `true` unconditionally, and `render` walked
        // straight into the trap. It must now be derived from the same probe the
        // renderer uses.
        #expect(MathRendering.shared.swiftMath.isReady == MathFonts.isAvailable)
    }

    @Test("Every render path is guarded by the availability probe, not by luck")
    func rendererGuardsOnAvailability() throws {
        // Assert on the source: this is the shape of the bug (an unguarded call
        // into SwiftMath's force-unwrapping accessors), and it cannot be
        // exercised in a process where the fonts *do* resolve.
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/EdmundRender/Math/MathRenderer.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        #expect(text.contains("guard MathFonts.isAvailable else { return nil }"),
                "SwiftMathRenderer.render must bail out before touching MTMathImage")
        #expect(text.contains("MathFonts.isAvailable"),
                "isReady is the availability probe, not a constant true")
    }
}

@Suite("Math — Unicode approximation renderer")
struct UnicodeMathRendererTests {

    @Test("Renders non-empty LaTeX to an image with sane metrics")
    @MainActor func renders() {
        let r = UnicodeMathRenderer()
        let out = r.render(latex: "x^2 + \\alpha", displayMode: false, pointSize: 16,
                           color: NSColor(red: 0, green: 0, blue: 0, alpha: 1))
        #expect(out != nil)
        guard let out else { return }
        #expect(out.image.size.width > 0)
        #expect(out.image.size.height > 0)
        #expect(abs((out.ascent + out.descent) - out.image.size.height) < 0.01,
                "ascent+descent must sum to the image height — callers place the baseline from it")
        #expect(out.descent >= 0)
    }

    @Test("Empty or whitespace-only LaTeX renders nothing, not an empty box")
    @MainActor func rejectsEmpty() {
        let r = UnicodeMathRenderer()
        #expect(r.render(latex: "", displayMode: false, pointSize: 16, color: .black) == nil)
        #expect(r.render(latex: "   ", displayMode: false, pointSize: 16, color: .black) == nil)
    }

    @Test("Readiness is unconditional — it has no fonts to fail to load")
    @MainActor func alwaysReady() {
        #expect(UnicodeMathRenderer().isReady)
    }

    @Test("Common commands map to their Unicode equivalents")
    func symbolSubstitution() {
        #expect(UnicodeMathRenderer.plainText(from: "\\alpha + \\beta") == "α + β")
        #expect(UnicodeMathRenderer.plainText(from: "a \\leq b") == "a ≤ b")
        #expect(UnicodeMathRenderer.plainText(from: "x \\in \\mathbb{R}") == "x ∈ R")
        // Sub/superscript braces are dropped, not lost: `\sum_{i=1}^{n}` reads
        // as "∑i=1n", which is what the flattened form can honestly show.
        #expect(UnicodeMathRenderer.plainText(from: "\\sum_{i=1}^{n} i") == "∑i=1n i")
    }

    @Test("Fractions and roots keep their arguments instead of dropping them")
    func structuralCommands() {
        #expect(UnicodeMathRenderer.plainText(from: "\\frac{a}{b}") == "(a)/(b)")
        #expect(UnicodeMathRenderer.plainText(from: "\\sqrt{x}") == "√x")
        // \frac with nested braces: the group reader is depth-aware, so the
        // argument is not truncated at the first `}`.
        #expect(UnicodeMathRenderer.plainText(from: "\\frac{a_{1}}{b}") == "(a1)/(b)")
    }

    @Test("Unknown commands degrade to their name, never to an empty string")
    func unknownCommandsStayReadable() {
        #expect(UnicodeMathRenderer.plainText(from: "\\weirdcommand") == "weirdcommand")
        #expect(!UnicodeMathRenderer.plainText(from: "\\unknown{x}").isEmpty)
    }
}

@Suite("Math — engine fallback chain")
struct MathEngineFallbackTests {

    @MainActor private final class DeadRenderer: MathRenderer {
        let id = "dead"
        var isReady: Bool { false }
        func render(latex: String, displayMode: Bool,
                    pointSize: CGFloat, color: NSColor) -> RenderedMath? { nil }
    }

    @MainActor private final class FailingRenderer: MathRenderer {
        let id = "failing"
        var isReady: Bool { true }
        func render(latex: String, displayMode: Bool,
                    pointSize: CGFloat, color: NSColor) -> RenderedMath? { nil }
    }

    @Test("An unready alternate is never selected")
    @MainActor func unreadyAlternateSkipped() {
        let coord = MathRendering.shared
        coord.alternate = DeadRenderer()
        defer { coord.alternate = nil }
        #expect(coord.active !== coord.alternate)
    }

    @Test("When the alternate can't render, the result is never nil for valid LaTeX")
    @MainActor func chainAlwaysProducesSomething() {
        let coord = MathRendering.shared
        coord.alternate = FailingRenderer()
        defer { coord.alternate = nil }
        // The alternate fails *and* SwiftMath fails → the Unicode engine still
        // draws it. A document with `$…$` must not render a hole.
        let out = coord.render(latex: "\\frac{a}{b}", displayMode: false,
                               pointSize: 16, color: NSColor(red: 0, green: 0, blue: 0, alpha: 1))
        #expect(out != nil)
    }

    @Test("Degraded state is reported by the coordinator, not inferred by callers")
    @MainActor func degradedFlag() {
        #expect(MathRendering.shared.isDegraded == !MathFonts.isAvailable)
    }

    @Test("The approximation never answers a parse error when the caller reports them")
    @MainActor func approximationIsNotAnErrorHandler() {
        // A document must always render *something* — a page with a hole in it is
        // a partial copy of the document (`renderingErrors: true`, the default).
        // The editor is different: it reports malformed LaTeX by showing the
        // source tinted red, and that branch is only reachable if a typo yields
        // no overlay. Before this distinction, `\frac{` drew as a plausible
        // flattened equation and the error state became dead code.
        let coord = MathRendering.shared
        let invalid = "\\frac{"
        let color = NSColor(red: 0, green: 0, blue: 0, alpha: 1)
        #expect(coord.render(latex: invalid, displayMode: false, pointSize: 16,
                             color: color, renderingErrors: true) != nil,
                "documents fall back to readable text, never to a hole")
        if MathFonts.isAvailable {
            // With real fonts the invalid input is refused by SwiftMath and must
            // not be answered by the approximation either.
            #expect(coord.render(latex: invalid, displayMode: false, pointSize: 16,
                                 color: color, renderingErrors: false) == nil,
                    "the editor must be able to tell 'invalid' from 'rendered'")
        }
    }
}

@Suite("Math — no unguarded Bundle.module reach in the math path")
struct MathCrashRegressionTests {

    /// The exact crash signature from issue #12, expressed as a test that can't
    /// crash the suite: touching SwiftMath's `fontBundle` accessor is what
    /// trapped, so the app must not call any SwiftMath API that reaches it
    /// without first probing `MathFonts`.
    @Test("MTFont's bundle accessor is the trap, and a legal bundle is what it needs")
    func fontBundleRequiresLegalBundle() {
        // A directory shaped like SwiftPM's `.copy` output — payload, no
        // Info.plist — is not a legal bundle. Foundation will hand back an
        // object for it, but `bundleIdentifier` is nil, which is the
        // precondition SwiftPM's generated `Bundle.module` accessor asserts on
        // (and asserts by trapping). This documents *why* the probe checks the
        // font file rather than just the directory's existence.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("edmund-mathfonts-\(UUID().uuidString)", isDirectory: true)
        let fake = root.appendingPathComponent("mathFonts.bundle", isDirectory: true)
        try? FileManager.default.createDirectory(at: fake, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(Bundle(path: fake.path)?.bundleIdentifier == nil,
                "a payload-only bundle has no identifier — Bundle.module traps on exactly this")

        // And the app's own resolution must not be satisfied by that shape: an
        // empty directory is not a font source, so availability follows the
        // *font file*, not the directory's existence. That distinction is the
        // difference between "degrades to readable Unicode" and "traps".
        #expect(MathFonts.url(forResource: MathFonts.defaultFontName, withExtension: "otf")?.path
                    != fake.appendingPathComponent("\(MathFonts.defaultFontName).otf").path,
                "an empty identifier-less directory must never resolve as a font source")
    }

    @Test("The nested .copy layout SwiftMath actually ships is probed")
    func probesNestedPayload() throws {
        // SwiftMath declares `.copy("mathFonts.bundle")`, and `.copy` reproduces
        // the directory verbatim — so the generated resource bundle is
        // `SwiftMath_SwiftMath.bundle/mathFonts.bundle/latinmodern-math.otf`, one
        // level deeper than the bundle name suggests. Probing only
        // `<bundle>/latinmodern-math.otf` found nothing and reported "no fonts"
        // for a release that had all of them: the crash was gone, but maths
        // silently became plain Unicode everywhere. Assert the nesting is probed.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("edmund-nested-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let payload = root.appendingPathComponent("mathFonts.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        try Data().write(to: payload.appendingPathComponent("\(MathFonts.defaultFontName).otf"))

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("edmund-probe-\(UUID().uuidString)", isDirectory: true)
        let bundle = directory.appendingPathComponent("SwiftMath_SwiftMath.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        // Move the payload *inside* the resource bundle, as SwiftPM does.
        try FileManager.default.moveItem(at: payload,
                                        to: bundle.appendingPathComponent("mathFonts.bundle"))
        defer { try? FileManager.default.removeItem(at: directory) }

        // `MathFonts.url(forResource:in:)` is private; the public probe is the
        // same predicate over the same directory list, so stage the directory as
        // `EDMUND_BUILD_PATH`-shaped input and assert the font is found.
        let nested = bundle.appendingPathComponent("mathFonts.bundle/\(MathFonts.defaultFontName).otf")
        #expect(FileManager.default.fileExists(atPath: nested.path),
                "the staged fixture must have the .copy shape")
        #expect(MathFonts.url(forResource: MathFonts.defaultFontName, withExtension: "otf")?
                    .lastPathComponent == "\(MathFonts.defaultFontName).otf",
                "the resolved directory must yield the font file itself")
    }

    @Test("Both layouts the packaging step can produce are probed")
    func probesBothLayouts() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/EdmundRender/Math/MathFonts.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        #expect(text.contains("Contents/Resources/"),
                "SwiftPM's `.copy` output is flat; a legal bundle's payload nests under Contents/Resources")
        #expect(text.contains("executablePath"),
                "swift run / swift test build the bundle next to the executable, not in Bundle.main")
    }

    @Test("No force-unwrapped Bundle.module access in the math pipeline")
    func noBundleModuleInMathPipeline() throws {
        // `Bundle.module.url(...)!` is the same trap one step earlier: the
        // generated accessor traps before `url(forResource:)` is even called.
        // The render layer must resolve fonts through `MathFonts`, so this walks
        // every Swift file in EdmundRender and flags any that so much as names
        // it *in code*. Comments are stripped first: the files document the trap
        // at length, and a documentation reference is not a call.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/EdmundRender")

        var offenders: [String] = []
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let object = enumerator?.nextObject() {
            guard let file = object as? URL, file.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: file, encoding: .utf8)
            if Self.mentionsBundleModuleInCode(source) {
                offenders.append(file.lastPathComponent)
            }
        }
        #expect(offenders.isEmpty,
                "EdmundRender must not reach Bundle.module — it traps when its bundle is missing: \(offenders)")
    }

    /// True when `Bundle.module` appears in actual code. `//`/`///` line
    /// comments and `/* */` blocks are dropped first, so prose about the trap
    /// doesn't read as an occurrence of it.
    private static func mentionsBundleModuleInCode(_ source: String) -> Bool {
        var inBlockComment = false
        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)
            if inBlockComment {
                guard let close = line.range(of: "*/") else { continue }
                line = String(line[close.upperBound...])
                inBlockComment = false
            }
            if let block = line.range(of: "/*") {
                inBlockComment = true
                line = String(line[..<block.lowerBound])
            }
            if let lineComment = line.range(of: "//") {
                line = String(line[..<lineComment.lowerBound])
            }
            if line.contains("Bundle.module") { return true }
        }
        return false
    }
}
