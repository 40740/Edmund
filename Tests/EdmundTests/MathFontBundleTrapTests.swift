import Testing
import Foundation
import AppKit
import CoreText
@testable import EdmundCore
import EdmundRender

// MARK: - MTFont.fontBundle is the trap, and 5.29.0 is about never reaching it
//
// Issue #12, one release later: 5.28.0 added `MathFonts` — an explicit,
// non-trapping font *probe* — and turned "fonts unreachable" into a recoverable
// state. The app still crashed on open, with the identical stack:
//
//   specialized static MTFont.fontBundle.getter
//     ← MTFont.__allocating_init(fontWithName:size:)
//     ← MTFontManager.font(withName:size:)
//     ← MTMathImage.init(latex:fontSize:textColor:labelMode:textAlignment:)
//     ← SwiftMathRenderer.render
//
// The reason is ordering. `MTMathImage` reads its `font` as a stored-property
// default:
//
//   public var font: MTFont? = MTFontManager.fontManager.defaultFont
//   public var defaultFont: MTFont? { latinModernFont(withSize: 20) }
//   public func font(withName:size:) -> MTFont? { MTFont(fontWithName:size:) }
//   static var fontBundle: Bundle { Bundle(url: Bundle.module.url(…)! )! }   // traps
//
// Constructing `MTMathImage` therefore builds the default font before a single
// line of caller code runs on it, and building it reaches `Bundle.module` inside
// SwiftMath. 5.28.0's `guard MathFonts.isAvailable else { return nil }` was in
// `render`, i.e. *after* that. Guarding the call is not the same as guarding the
// trap.
//
// These tests hold the shape that makes the fix real: the fonts are resolved
// failable-ly, the bundle they live in is published where SwiftMath's accessor
// looks, and every SwiftMath font object is built only after that.

@Suite("Math — the trap is in MTMathImage's own initialisation")
struct MathTrapOrderingTests {

    enum AnalysisError: Error, CustomStringConvertible {
        case notFound(String)
        var description: String {
            switch self { case .notFound(let declaration): return "could not locate \(declaration)" }
        }
    }

    /// The repository root, from this file's own location.
    private static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EdmundTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    private static func source(_ relativePath: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// The SwiftMath checkout that built this package, via SwiftPM's own artifact
    /// layout — the same `.build` tree `MathFonts` probes for its fonts, so if the
    /// fonts are reachable the sources are too.
    private static func swiftMathSource(_ relativePath: String) throws -> String {
        let checkouts = root.appendingPathComponent(".build/checkouts/SwiftMath")
        return try String(contentsOf: checkouts.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// The body of a declaration: its own line plus every following line indented
    /// deeper than it. Stable against the file growing members above or below.
    private static func body(of declaration: String, in text: String) throws -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains(declaration) }) else {
            throw AnalysisError.notFound(declaration)
        }
        let indent = lines[start].prefix { $0 == " " }.count
        var collected = [lines[start]]
        for line in lines[(start + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, line.prefix { $0 == " " }.count <= indent { break }
            collected.append(line)
        }
        return collected.joined(separator: "\n")
    }

    /// The premise of the whole fix, read off SwiftMath's own source.
    @Test("MTMathImage acquires its font eagerly, through MTFontManager")
    func mathImageAcquiresItsFontEagerly() throws {
        let text = try Self.swiftMathSource("Sources/SwiftMath/MathRender/MTMathImage.swift")
        let font = try Self.body(of: "public var font: MTFont? =", in: text)
        #expect(font.contains("MTFontManager.fontManager.defaultFont"),
                "the default value runs inside MTMathImage.init — that is the trap")
    }

    @Test("MTFontManager's font funnel ends at the force-unwrapped Bundle.module accessor")
    func fontManagerReachesTheAccessor() throws {
        let manager = try Self.swiftMathSource("Sources/SwiftMath/MathRender/MTFontManager.swift")
        let funnel = try Self.body(of: "public func font(withName name:String, size:CGFloat)",
                                  in: manager)
        #expect(funnel.contains("MTFont(fontWithName: name, size: size)"),
                "MTFont(fontWithName:) is the only way into the font bundle")

        let font = try Self.swiftMathSource("Sources/SwiftMath/MathRender/MTFont.swift")
        let accessor = try Self.body(of: "static var fontBundle:Bundle", in: font)
        #expect(accessor.contains("Bundle.module"),
                "the accessor is Bundle.module — Foundation's generated one, which traps")
        #expect(accessor.contains("!"),
                "and it is force-unwrapped at both ends, so there is no throwing path")
    }

    /// The regression. In 5.28.0 the guard was inside `render`, i.e. after
    /// `MTMathImage`'s initialiser had already reached the trap — so the release
    /// that was meant to fix this crash crashed the same way.
    @Test("SwiftMathRenderer consults the acquired state before constructing anything")
    func rendererDoesNotOutsourceTheGuard() throws {
        let text = try Self.source("Sources/EdmundRender/Math/MathRenderer.swift")
        let render = try Self.body(of: "public func render(latex: String, displayMode: Bool,", in: text)
        guard let guardRange = render.range(of: "MathFonts.prepare()"),
              let constructorRange = render.range(of: "MTMathImage(") else {
            Issue.record("render must both consult MathFonts.prepare() and build an MTMathImage")
            return
        }
        #expect(guardRange.lowerBound < constructorRange.lowerBound,
                "the fonts must be known-acquired before MTMathImage.init runs its font default")
        #expect(render.contains("guard MathFonts.prepare()"),
                "and it must be a bail-out, not a comment")
    }

    @Test("The bootstrap runs before anything can render")
    func appPreparesFontsAtLaunch() throws {
        let main = try Self.source("Sources/edmd/App/main.swift")
        guard let bootstrap = main.range(of: "MathRendering.bootstrap()"),
              let launch = main.range(of: "let app = NSApplication.shared") else {
            Issue.record("main.swift must bootstrap the fonts and start the app")
            return
        }
        #expect(bootstrap.lowerBound < launch.lowerBound,
                "font acquisition is a startup step — nothing may render before it")
    }

    @Test("The editor's math path asserts the same bootstrap")
    func editorMathPathBootstraps() throws {
        let text = try Self.source("Sources/EdmundCore/Rendering/EditorTextView+MathRendering.swift")
        #expect(text.contains("guard MathRendering.bootstrap()"),
                "a host that builds an editor without the app's main must still be safe")
    }

    @Test("SwiftMath's font objects are built in exactly one place")
    func fontAccessIsCentralised() throws {
        let directory = Self.root.appendingPathComponent("Sources/EdmundRender")
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        var offenders: [String] = []
        for file in files where file.lastPathComponent != "MathFonts.swift" {
            let code = ((try? String(contentsOf: file, encoding: .utf8)) ?? "")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false)
                        .first.map(String.init) ?? "" }
                .joined(separator: "\n")
            // `MathFonts.swift` is the one file allowed to build a font object —
            // it is where the acquisition happens. If any other file does, the
            // ordering is lost one call site at a time. (SwiftMath itself lives
            // under `.build`, so it is not enumerated here.)
            if code.contains("MTFont(") || code.contains("MTFontManager") {
                offenders.append(file.lastPathComponent)
            }
        }
        #expect(offenders.isEmpty,
                "font objects must be reached only after the bundle is published: \(offenders)")
    }

    @Test("The render layer still never names Bundle.module")
    func renderLayerAvoidsBundleModule() throws {
        // The syntax-definition side of this trap was issue #8; the font side is
        // issue #12. Neither may reappear, in code (the comments explain both).
        let code = try Self.source("Sources/EdmundRender/Math/MathFonts.swift")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false)
                    .first.map(String.init) ?? "" }
            .joined(separator: "\n")
        #expect(!code.contains("Bundle.module"),
                "the resolver must not use the accessor whose absence it exists to handle")
    }
}

@Suite("Math — the bundle SwiftMath looks in is published at startup")
struct MathFontPublishingTests {

    @Test("Resolution finds the font, and the enclosing bundle is the one published")
    @MainActor func containerIsTheFontsBundle() throws {
        guard let directory = MathFonts.directory else {
            Issue.record("the test bundle is mirrored with the app's resource bundles; fonts must resolve")
            return
        }
        let container = try #require(MathFonts.containerBundle(for: directory),
                                     "the font's directory is inside a resource bundle or the app")
        #expect(container.bundleURL.path.hasPrefix(directory.deletingLastPathComponent().path)
                || directory.path.hasPrefix(container.bundleURL.path),
                "the container must be an ancestor of the font directory")
        #expect(["app", "appex", "bundle"].contains(container.bundleURL.pathExtension),
                "publishing a non-bundle would leave SwiftMath looking in the wrong place")
    }

    @Test("Bundle.main answers with the fonts' bundle after publishing")
    @MainActor func publishingMakesBundleMainFindTheFonts() throws {
        // The behavioural half of `PulseFonts`: after the handshake, the query
        // SwiftMath's accessor performs — `Bundle.main.resourceURL` — resolves to
        // a directory that contains the font bundle it asks for.
        let prepared = MathFonts.prepare()
        guard prepared, let directory = MathFonts.directory else {
            // A build with no fonts: the supported degraded state, checked below.
            return
        }
        let resource = try #require(Bundle.main.resourceURL)
        let asked = resource.appendingPathComponent("mathFonts.bundle")
        let nested = asked.appendingPathComponent("latinmodern-math.otf")
        #expect(FileManager.default.fileExists(atPath: nested.path)
                || FileManager.default.fileExists(atPath: directory
                    .appendingPathComponent("latinmodern-math.otf").path)
                || directory.path.hasPrefix(resource.path),
                "after prepare(), the accessor's own query must land on the fonts")
    }

    @Test("The process this suite runs in resolves fonts the way the app does")
    @MainActor func diagnosticState() {
        // Reported, not asserted beyond what the design guarantees: these are the
        // four facts that decide whether the suite grades typeset maths or the
        // approximation, and when one of them is wrong the *other* tests' failures
        // are only symptoms.
        print("[MathFonts] Bundle.main.bundleURL        = \(Bundle.main.bundleURL.path)")
        print("[MathFonts] Bundle.main.resourceURL      = \(Bundle.main.resourceURL?.path ?? "nil")")
        print("[MathFonts] resolved directory           = \(MathFonts.directory?.path ?? "nil")")
        print("[MathFonts] container bundle             = \(MathFonts.containerBundle(for: MathFonts.directory ?? URL(fileURLWithPath: "/")).map(\.bundleURL.path) ?? "nil")")
        print("[MathFonts] prepare()                    = \(MathFonts.prepare())")
        print("[MathFonts] font                         = \(MathFonts.font.map { String(describing: type(of: $0)) } ?? "nil")")
    }

    @Test("prepare() is idempotent and its answer is stable")
    @MainActor func prepareIsIdempotent() {
        let first = MathFonts.prepare()
        for _ in 0..<3 { #expect(MathFonts.prepare() == first) }
        #expect(MathRendering.bootstrap() == first)
        #expect(MathRendering.shared.swiftMath.isReady == MathFonts.isAvailable)
        #expect(MathRendering.shared.isDegraded == !first)
    }
}

@Suite("Math — the degradation path has no font dependency")
struct MathFallbackIndependenceTests {

    private static func source(_ relativePath: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// `UnicodeMathRenderer` used to draw with `Asana-Math` *by name* — a font
    /// that, in the shipped app, lives inside `mathFonts.bundle`: the same bundle
    /// whose absence is what puts the process on this path. A fallback that needs
    /// the thing that failed is not a fallback.
    @Test("The approximation does not depend on the bundle it exists to replace")
    func approximationDoesNotNeedTheBundle() throws {
        let text = try Self.source("Sources/EdmundRender/Math/UnicodeMathRenderer.swift")
        let code = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false)
                    .first.map(String.init) ?? "" }
            .joined(separator: "\n")
        #expect(!code.contains("MathFonts.substituteFontName"),
                "naming the bundled font makes the last resort depend on the font that isn't there")
        #expect(code.contains("hasMathGlyphs"),
                "it must ask whether a font can draw maths, then fall through if it can't")
        #expect(code.contains("NSFont.systemFont"),
                "and the floor is a font the OS always has")
    }

    @Test("The approximation renders with no fonts on disk at all")
    @MainActor func approximationRendersRegardless() throws {
        let renderer = UnicodeMathRenderer()
        #expect(renderer.isReady)
        let out = try #require(renderer.render(latex: "\\frac{a}{b} + \\alpha", displayMode: false,
                                               pointSize: 16, color: .black))
        #expect(out.image.size.width > 0 && out.image.size.height > 0)
        #expect(abs((out.ascent + out.descent) - out.image.size.height) < 0.01,
                "ascent+descent must sum to the image height: callers place the baseline from it")
    }

    @Test("The system font it falls back to really can draw the symbols")
    @MainActor func systemFontCoversTheOutput() {
        // The probe the renderer uses, asserted on the floor it can rely on — so
        // a future macOS whose system font lost the arrows or signs fails here
        // rather than shipping boxes.
        let font = NSFont.systemFont(ofSize: 16) as CTFont
        let sample = Array("\u{2211}\u{221A}\u{2202}\u{2264}\u{03B1}".unicodeScalars)
        var characters = sample.map { UniChar($0.value) }
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        let ok = CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
        #expect(ok && !glyphs.contains(0),
                "the approximation's floor must be able to draw ∑ √ ∂ ≤ α")
    }
}
