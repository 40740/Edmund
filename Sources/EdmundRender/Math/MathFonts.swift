import AppKit
import CoreText
import SwiftMath

// MARK: - MathFonts
//
// Where the bundled OpenType math fonts live, and — more importantly — when
// we are allowed to touch them.
//
// SwiftMath ships its fonts in a nested SwiftPM resource bundle
// (`Sources/SwiftMath/mathFonts.bundle`) and reaches them through two calls that
// this app cannot make safe:
//
//   MTFont.fontBundle      → `Bundle(url: Bundle.module.url(forResource:
//                             "mathFonts", withExtension: "bundle")!)!`
//   BundleManager (MathFont/MTFontV2)
//                          → `Bundle.module.url(...)`, and on failure
//                            `fatalError("…ondemand loading failed")`
//
// `Bundle.module`'s generated accessor traps (`EXC_BREAKPOINT` / `SIGTRAP`) when
// the bundle it was compiled against can't be found or isn't a legal bundle —
// there is no throwing path, and both funnels above are `!`.
//
// 5.28.0 tried to make that a recoverable condition by probing the directory
// ourselves and guarding the render call with `MathFonts.isAvailable`. That is
// half a fix, and the missing half is *ordering*: `MTMathImage` acquires its
// font in a stored-property default,
//
//   public var font: MTFont? = MTFontManager.fontManager.defaultFont
//
// which runs *inside its initialiser* — before the caller gets an object to
// guard anything on. `SwiftMathRenderer.render`'s
// `guard MathFonts.isAvailable else { return nil }` therefore evaluated after
// the trap, and 5.28.0 crashed the same way 5.27.0 did (issue #12).
//
// So the fix is not a guard but an acquisition order:
//
//   1. This file resolves the *bundle* that contains the fonts through
//      `Bundle(url:)` — a failable initialiser, no `Bundle.module`, no `!`.
//      Nothing on this path can trap.
//   2. `PulseFonts` makes that bundle the process's main bundle: CoreFoundation
//      derives the main bundle from the process path (`_CFProcessPath()` reads
//      `$CFProcessPath` on macOS before falling back to the real executable), so
//      pointing that at the fonts' bundle is enough — and the generated accessor
//      then resolves through it. Everything involved is an exported symbol.
//   3. Only once that holds does anything call into SwiftMath at all — and the
//      first call is `MathRendering.bootstrap()` from `main`, before a document
//      or even an NSApplication exists.
//
// Every step above declines instead of trapping when its precondition is
// missing, so a build that ships no fonts still opens documents — with the
// Unicode approximation — rather than dying.

public enum MathFonts {

    /// SwiftMath's default font (`MTFontManager.defaultFont` →
    /// `latinModernFont(withSize: 20)`).
    public static let defaultFontName = "latinmodern-math"

    /// Where `UnicodeMathRenderer` looks for an OpenType MATH font to draw the
    /// approximation with, *when one is reachable*. It is an optimisation, not a
    /// dependency: the renderer falls through to a system font whenever this
    /// can't be loaded — including exactly the case this whole file exists for,
    /// a build whose `mathFonts.bundle` is missing.
    public static func substituteFontURL() -> URL? {
        url(forResource: "Asana-Math", withExtension: "otf")
    }

    // MARK: Resolution (failable, non-trapping)

    /// Directory holding `latinmodern-math.otf` + its `.plist`, resolved on
    /// first use. `nil` means the fonts aren't reachable in this process, which
    /// callers must treat as "no SwiftMath", never as a reason to trap.
    public static let directory: URL? = resolveDirectory()

    /// Whether SwiftMath can render in this process.
    public static var isAvailable: Bool { directory != nil }

    /// What to hand SwiftMath as its main bundle, or nil when the fonts aren't
    /// reachable at all — in which case there is nothing to prepare and every
    /// caller must take the approximation path instead.
    ///
    /// Only the bundle that actually *contains* the font is handed over. This
    /// matters for a `.app`: `Bundle.main.resourceURL` is
    /// `Edmund.app/Contents/Resources`, so `mathFonts` resolves to
    /// `…/Contents/Resources/mathFonts.bundle` and a bare
    /// `appendingPathComponent("mathFonts.bundle")` finds nothing — a miss that
    /// is silent, because the case it protects against is the exception.
    public static func containerBundle(for directory: URL) -> Bundle? {
        let isBundle = { (url: URL) in
            ["app", "appex", "bundle"].contains(url.pathExtension)
        }
        var candidates: [URL] = []
        // The directory can *be* the bundle: `swift run`/`swift test` build
        // `mathFonts.bundle`/`SwiftMath_SwiftMath.bundle` right next to the
        // binary, and the resolver returns that path itself. Checking only the
        // parent here silently found nothing in the test process — which is the
        // one place it can't be allowed to, since the suite would then grade the
        // Unicode fallback while the app ships SwiftMath.
        if isBundle(directory) {
            candidates.append(directory)
        }
        if directory.path.hasSuffix("/Contents/Resources") {
            // A legal macOS bundle keeps its payload here; the bundle is two
            // levels up, not one.
            candidates.append(directory.deletingLastPathComponent()
                .deletingLastPathComponent())
        }
        candidates.append(directory.deletingLastPathComponent())
        for candidate in candidates where isBundle(candidate) {
            if let bundle = Bundle(url: candidate) { return bundle }
        }
        return nil
    }

    /// `mathFonts.bundle` is a *resource bundle*: SwiftPM's `.copy` lays its
    /// payload out flat (`<bundle>/latinmodern-math.otf`) and Foundation looks
    /// for it in `Contents/Resources` once `build-app.sh` has made it a legal
    /// bundle. Both layouts are probed because either can be the one on disk,
    /// depending on how the app was packaged.
    ///
    /// Candidates, in order:
    ///
    ///   1. `Bundle.main.resourceURL` and `Bundle.main.bundleURL`, under
    ///      `mathFonts.bundle` / `SwiftMath_SwiftMath.bundle` / `SwiftMath.bundle`.
    ///      This is the app and the Quick Look appex (a `.appex`'s `Bundle.main`
    ///      *is* the appex).
    ///   2. The executable's directory and its parent — where `swift run` and
    ///      `swift test` put the resource bundle.
    ///   3. `.build/{release,debug}` under the working directory and the repo
    ///      root (reachable as this file's ancestors). `swift test` runs the
    ///      .xctest out of a temporary directory, so (2) misses on macOS.
    ///   4. `EDMUND_BUILD_PATH`, if set — an explicit override for a relocated
    ///      build, accepted however it was spelled (root, `.build`, or a config
    ///      directory under it).
    ///
    /// A candidate only counts when the *font file* is present: an empty
    /// directory with the bundle's name is exactly the identifier-less shape
    /// that traps, so its mere existence must not read as "fonts available".
    private static func resolveDirectory() -> URL? {
        var candidates: [URL] = []

        // 1. The app bundle's Resources. `build-app.sh` copies SwiftPM's
        //    per-target resource bundles here, and the appex's own bundles live
        //    in its Resources too — so Quick Look finds them without anything
        //    special.
        let mainResources = Bundle.main.resourceURL
        let mainBundleURL = Bundle.main.bundleURL
        for root in [mainResources, mainBundleURL].compactMap({ $0 }) {
            candidates.append(root.appendingPathComponent("mathFonts.bundle"))
            candidates.append(root.appendingPathComponent("SwiftMath_SwiftMath.bundle"))
            candidates.append(root.appendingPathComponent("SwiftMath.bundle"))
        }

        // 2. Next to the executable. `swift run edmd` and `swift test` execute
        //    from `.build/<config>` and build the resource bundle right there
        //    (`.build/<config>/mathFonts.bundle`, plus a
        //    `SwiftMath_SwiftMath.bundle` alias) — no bundle staging needed.
        let executable = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
        for root in [executable.deletingLastPathComponent(),
                     executable.deletingLastPathComponent().deletingLastPathComponent()] {
            candidates.append(root.appendingPathComponent("mathFonts.bundle"))
            candidates.append(root.appendingPathComponent("SwiftMath_SwiftMath.bundle"))
            candidates.append(root.appendingPathComponent("SwiftMath.bundle"))
        }

        // 3. Build directories SwiftPM may have used without leaving anything
        //    next to the binary.
        //
        //    `swift test` runs the .xctest bundle out of a temporary directory on
        //    macOS, and the resource bundle sits in the *build* directory — so
        //    "next to the executable" and "next to its parent" both miss. Probe
        //    the conventional `.build/<config>` under the working directory and
        //    the repo root (reached as `#filePath`'s ancestors), plus an explicit
        //    override, since a wrong guess here is silent: maths quietly becomes
        //    the Unicode approximation everywhere including CI.
        var roots = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            URL(fileURLWithPath: #filePath)          // Sources/EdmundRender/Math/...
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent(),
        ]
        if let override = ProcessInfo.processInfo.environment["EDMUND_BUILD_PATH"] {
            // Accept the build directory however it was spelled: the repo root,
            // the build path itself (`.../.build`), or a config directory
            // (`.../.build/release`) — all three are probed as-is and then with
            // the conventional suffixes below.
            let url = URL(fileURLWithPath: override)
            candidates.append(url.appendingPathComponent("mathFonts.bundle"))
            candidates.append(url.appendingPathComponent("SwiftMath_SwiftMath.bundle"))
            roots.append(url)
        }
        for root in roots {
            for config in ["release", "debug", ""] {
                let base = config.isEmpty ? root.appendingPathComponent(".build")
                                          : root.appendingPathComponent(".build").appendingPathComponent(config)
                candidates.append(base.appendingPathComponent("mathFonts.bundle"))
                candidates.append(base.appendingPathComponent("SwiftMath_SwiftMath.bundle"))
                candidates.append(base.appendingPathComponent("SwiftMath.bundle"))
            }
        }

        for candidate in candidates where hasFont(named: defaultFontName, in: candidate) {
            return candidate
        }
        return nil
    }

    private static func hasFont(named name: String, in directory: URL) -> Bool {
        url(forResource: name, withExtension: "otf", in: directory) != nil
    }

    /// The payload directories under `bundle`, in probe order.
    ///
    /// SwiftMath declares its fonts as `.copy("mathFonts.bundle")`, and `.copy`
    /// reproduces the directory *verbatim*: the generated resource bundle is
    /// `SwiftMath_SwiftMath.bundle/mathFonts.bundle/<font>.otf`, one nesting
    /// deeper than the app ever assumed. Checking only `<bundle>/<font>.otf`
    /// therefore found nothing and reported "no fonts" for a release that had
    /// every one of them — which is worse than the crash it replaced, because it
    /// is silent. A legal macOS bundle additionally keeps its payload under
    /// `Contents/Resources`, so all three shapes are probed.
    private static func payloadDirectories(in bundle: URL) -> [URL] {
        var directories: [URL] = []
        for nested in ["", "mathFonts.bundle",
                       "Contents/Resources", "Contents/Resources/mathFonts.bundle"] {
            directories.append(nested.isEmpty ? bundle : bundle.appendingPathComponent(nested))
        }
        return directories
    }

    /// A file inside the resolved directory, tolerating the flat (`.copy`),
    /// `mathFonts.bundle`-nested and `Contents/Resources` layouts.
    public static func url(forResource name: String, withExtension ext: String) -> URL? {
        guard let directory else { return nil }
        return url(forResource: name, withExtension: ext, in: directory)
    }

    private static func url(forResource name: String, withExtension ext: String,
                            in directory: URL) -> URL? {
        let fm = FileManager.default
        for root in payloadDirectories(in: directory) {
            let file = root.appendingPathComponent("\(name).\(ext)")
            if fm.fileExists(atPath: file.path) { return file }
        }
        return nil
    }

    // MARK: Preparation

    /// Resolve the fonts and point SwiftMath at them, exactly once.
    ///
    /// `PulseFonts.publish` is what makes SwiftMath's own `Bundle.module`
    /// accessor succeed where it would otherwise trap — and it is the same
    /// handshake `MTFont.fontBundle.getter` performs as its first move, so by
    /// the time SwiftMath is asked, the answer is already in place. Doing it
    /// here (startup, before a document exists) is the point; doing it per
    /// equation would put the trap back on the render path.
    ///
    /// Idempotent: the second and later calls return the first result.
    private static let prepared: Bool = {
        guard isAvailable, let directory else { return false }
        guard let container = containerBundle(for: directory) else {
            // The fonts are on disk but not inside anything Foundation calls a
            // bundle, so SwiftMath would miss and trap. Decline: documents render
            // through the approximation.
            return false
        }
        // Publishing the bundle this process already *is* would be a no-op at
        // best. It happens under `swift run` / `swift test` (the fonts' bundle is
        // a directory in `.build`, and `Bundle.main` is the .xctest or the
        // binary) and for an appex reading its own `Contents/Resources`. In both
        // cases the answer is the same as the check's: the fonts are reachable.
        if container.bundleURL != Bundle.main.bundleURL,
           container.bundleURL != Bundle.main.resourceURL {
            _ = PulseFonts.publish(container)
        }
        // The precondition is a fact about Foundation, not about the publish
        // step's return value: would a `Bundle.module`'s `Bundle.main` fallback
        // find the font bundle it asks for? Ask it. This is what makes the
        // renderer's `enable` a *verified* state — and it is testable in the
        // suite, which runs under a `Bundle.main` no publish can move.
        return mainBundleCanSeeFontBundle()
    }()

    /// Whether `Bundle.main` — the fallback a generated `Bundle.module` accessor
    /// consults — can resolve `mathFonts` to the bundle that holds the fonts.
    ///
    /// Checked the way the accessor would: by looking for the resource where it
    /// would look. A `nil` here is a supported state (the approximation takes
    /// over), never something to assert on.
    private static func mainBundleCanSeeFontBundle() -> Bool {
        guard let resource = Bundle.main.resourceURL ?? Bundle.main.bundleURL as URL? else {
            return false
        }
        for name in ["mathFonts.bundle", "SwiftMath_SwiftMath.bundle", "SwiftMath.bundle"] {
            if hasFont(named: defaultFontName, in: resource.appendingPathComponent(name)) {
                return true
            }
        }
        return false
    }

    /// Whether the fonts were acquired before anything was rendered. A `false`
    /// here is a normal, supported state — the approximation engine takes over —
    /// not a failure to report.
    @discardableResult
    public static func prepare() -> Bool { prepared }

    /// The one `MTFont` this process resolves, created after the fonts are in
    /// place — the single place a SwiftMath font object is ever built.
    ///
    /// Every font object is a `Bundle.module` lookup, and that lookup is the
    /// trap, so there is exactly one, made while the bundle is known to be
    /// findable. Consumers get it *by identity* (`MathFonts.font`), never by
    /// asking SwiftMath again: `MTMathUILabel.font` is settable, so a freshly
    /// built label can be handed this and then never consult the bundle.
    /// Resolved *after* `prepare()` has published the bundle, through SwiftMath's
    /// own by-name lookup.
    ///
    /// That lookup is the `Bundle.module` path — the trap — and it is deliberately
    /// taken here and nowhere else, because this is the one moment it is known to
    /// succeed: `prepare()` has just made the fonts' bundle the one Foundation
    /// treats as the process's, which is exactly what the accessor's fallbacks
    /// read. Reaching for the font anywhere else would re-open the window
    /// `MTMathImage.init` used to crash in.
    ///
    /// `MTFont(fontWithName:)` is the only entry point available: the
    /// file-based members it fills in are internal to SwiftMath, so a font cannot
    /// be built from a URL from out here.
    @MainActor
    public static let font: MTFont? = {
        guard isAvailable else { return nil }
        // `prepare()` has published the fonts' bundle where SwiftMath's accessor
        // looks (or found that it already is there — the `.xctest` and appex
        // cases, where `Bundle.main` is the fonts' own container). Either way the
        // by-name lookup below is the moment it is safe to make, and it is the
        // only entry point: the file-based members of `MTFont` are internal to
        // SwiftMath, so the font cannot be assembled from the path we resolved.
        _ = prepare()
        return MTFontManager().defaultFont
    }()

    /// A typesetting target carrying the resolved font. Fresh per expression, so
    /// nothing stale can be reused across `.text`/`.display` — a label caches its
    /// display list and does *not* invalidate it on a `labelMode` change, which
    /// makes a shared, reconfigured label quietly wrong for the second mode it is
    /// asked for.
    @MainActor
    static func panel(latex: String, mode: MTMathUILabelMode, size: CGFloat) -> MTMathUILabel? {
        guard let font else { return nil }
        let label = MTMathUILabel()
        label.font = font
        label.latex = latex
        label.fontSize = size
        label.labelMode = mode
        label.layout()
        return label
    }
}