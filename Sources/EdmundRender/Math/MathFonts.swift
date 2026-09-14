import Foundation

// MARK: - MathFonts
//
// SwiftMath's fonts, made reachable *before* SwiftMath looks for them.
//
// SwiftMath ships its math fonts in one SwiftPM resource bundle
// (`Sources/SwiftMath/mathFonts.bundle`) and reaches them through a single
// accessor this app cannot make safe:
//
//     static var fontBundle: Bundle {
//         Bundle(url: Bundle.module.url(forResource: "mathFonts", withExtension: "bundle")!)!
//     }
//
// `Bundle.module`'s generated accessor calls `fatalError` when the bundle it was
// compiled against can't be found, and the accessor above force-unwraps the
// result on top of that. There is no throwing path and nothing a caller can
// intercept — the process dies (`EXC_BREAKPOINT` / `SIGTRAP`).
//
// That is what crashed the app on the main thread the moment a document
// contained a `$…$`:
//
//     restyleBlock → mathOverlay → MathRendering.render → MTMathImage.init
//       → MTFontManager.font → MTFont.fontBundle → trap
//
// It is also why guarding the *call* does not fix it. In SwiftMath, `font` is a
// stored property with a default value —
// `public var font: MTFont = .latinModernFont` — and `.latinModernFont` resolves
// `MTFontManager.fontManager.defaultFont`, i.e. `MTFont(fontWithName:size:)`,
// which reads `MTFont.fontBundle`. Swift evaluates that *inside* `MTFont.init`,
// before `MTMathImage` exists. A `guard` placed in the caller's `render` runs
// after the trap has already fired. Guarding the call cannot guard the trap.
//
// What does work is making SwiftMath's own lookup succeed: the generated
// accessor searches `Bundle.main.resourceURL`, then `Bundle(for: BundleFinder.self)`'s
// resources, then `Bundle.main.bundleURL`, for `SwiftMath_SwiftMath.bundle`. Ship
// the resource bundle in one of those places, and `Bundle.module` never gets as
// far as `fatalError`.
//
// So this resolves the directory the fonts are actually in — no `Bundle.module`,
// no force-unwraps — and reports it. `SwiftMathRenderer` then reads that fact
// instead of calling into SwiftMath blind. Missing fonts are a *normal* state
// ("no typesetting engine"), never a trap: equations fall back to flattened
// Unicode and every other part of the document is unaffected.
//
// Cost: one directory probe per process, at startup. The render path does no
// file-system work, and nothing here allocates the 7 MB font bundle unless an
// equation is actually rendered.
public enum MathFonts {

    /// SwiftMath's default font (`MTFontManager.defaultFont` →
    /// `latinModernFont(withSize:)`). The editor and `DocumentHTML` only ever
    /// typeset with this one, so this file's presence decides whether maths is
    /// available at all.
    public static let defaultFontName = "latinmodern-math"

    /// Whether SwiftMath can typeset in this process.
    ///
    /// Decided once, on first use, and then cached: the resolution walks a small
    /// fixed list of directories, and the answer cannot change while the process
    /// runs.
    public static var isAvailable: Bool { directory != nil }

    /// The directory holding `latinmodern-math.otf` + its `.plist`. `nil` when
    /// the fonts aren't reachable in this process, which callers must treat as
    /// "no typesetting engine" — never as a reason to trap.
    public static let directory: URL? = resolveDirectory()

    /// The directory, resolved once. Kept separate from the public `directory`
    /// so the resolution is testable without the `static let` cache.
    static func resolveDirectory() -> URL? {
        for candidate in candidates() where hasFont(named: defaultFontName, in: candidate) {
            return candidate
        }
        return nil
    }

    // MARK: - Where the fonts can be

    /// Candidates, in the order SwiftMath's own accessor would consider them, so
    /// a hit here is also a hit there:
    ///
    ///   1. `Bundle.main`'s resource directory and its bundle root, under
    ///      `SwiftMath_SwiftMath.bundle` / `mathFonts.bundle`. This is the app,
    ///      and the Quick Look appex (whose `Bundle.main` *is* the appex).
    ///   2. Next to the executable and one level up, where `swift run` and
    ///      `swift test` leave the resource bundle.
    ///   3. The conventional `.build/<config>` directories under the working
    ///      directory and the package root — `swift test` runs the `.xctest` out
    ///      of a temporary directory, so (2) misses on macOS.
    ///
    /// A candidate only counts when the *font file* is present: a directory with
    /// the bundle's name but no fonts is exactly the identifier-less shape that
    /// traps, so its mere existence must not read as "fonts available".
    private static func candidates() -> [URL] {
        var roots: [URL] = []

        if let resources = Bundle.main.resourceURL { roots.append(resources) }
        roots.append(Bundle.main.bundleURL)

        if let exe = Bundle.main.executablePath ?? CommandLine.arguments.first, !exe.isEmpty {
            let url = URL(fileURLWithPath: exe)
            roots.append(url.deletingLastPathComponent())
            roots.append(url.deletingLastPathComponent().deletingLastPathComponent())
        }

        roots.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath))

        // `#filePath` is …/Sources/EdmundRender/Math/MathFonts.swift; four levels
        // up is the package root.
        var packageRoot = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { packageRoot.deleteLastPathComponent() }
        roots.append(packageRoot)

        let names = ["SwiftMath_SwiftMath.bundle", "mathFonts.bundle"]
        var out: [URL] = []
        for root in roots {
            for name in names { out.append(root.appendingPathComponent(name)) }
            for config in ["release", "debug"] {
                let base = root.appendingPathComponent(".build").appendingPathComponent(config)
                for name in names { out.append(base.appendingPathComponent(name)) }
            }
        }
        return out
    }

    /// `mathFonts.bundle` is a *resource bundle*, and three shapes of it are real
    /// depending on how the app was assembled: the payload flat beside the
    /// bundle's `Info.plist` (SwiftPM's `.copy`), the payload under
    /// `Contents/Resources` (a legal macOS bundle), and the nested
    /// `mathFonts.bundle/` that `.copy("mathFonts.bundle")` reproduces verbatim
    /// — one level deeper than the bundle name suggests.
    static func hasFont(named font: String, in dir: URL) -> Bool {
        for sub in ["", "mathFonts.bundle", "Contents/Resources",
                    "Contents/Resources/mathFonts.bundle"] {
            let path = dir.appendingPathComponent(sub).appendingPathComponent("\(font).otf")
            if FileManager.default.fileExists(atPath: path.path) { return true }
        }
        return false
    }

    /// The directory SwiftMath's `fontBundle` would resolve to from *this* bundle
    /// — the one its generated accessor computes. Exposed for the packaging
    /// tests, which assert the app ships the fonts in a place that lookup finds.
    public static func fontDirectory(in bundle: Bundle) -> URL? {
        for name in ["SwiftMath_SwiftMath.bundle", "mathFonts.bundle"] {
            for base in [bundle.resourceURL, bundle.bundleURL].compactMap({ $0 }) {
                let candidate = base.appendingPathComponent(name)
                if hasFont(named: defaultFontName, in: candidate) { return candidate }
            }
        }
        return nil
    }
}
