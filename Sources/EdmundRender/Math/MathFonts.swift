import Foundation

// MARK: - MathFonts
//
// Where the bundled OpenType math fonts live, and — more importantly — where
// they are *allowed to be missing*.
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
// there is no throwing path, and both funnels above are `!`. The app ships the
// bundle next to the executable and is fine; the Quick Look appex, the tests and
// any packaged copy are not guaranteed to. That is issue #12: opening a document
// with any `$…$` in it crashed `edmd` on the main thread, in
// `MTFont.fontBundle.getter`, while restyling the block that contained the
// equation.
//
// So the app resolves the font directory itself — no `Bundle.module`, no
// force-unwraps — and treats "fonts unavailable" as a normal state:
// `SwiftMathRenderer` falls back to a Unicode-approximation renderer and the
// editor keeps working with every other part of the document intact.
//
// The resolution must answer *SwiftMath's* question, not a nearby one. v5.28.1
// probed more places than `Bundle.module` does (the executable's directory, the
// working directory, `.build/<config>`) and accepted `mathFonts.bundle` as a
// resource-bundle name. A layout could therefore satisfy that probe while
// SwiftMath's own lookup reached `fatalError` or a force-unwrap — the guard
// passed, the process trapped anyway, and issue #14 survived the fix meant to
// close it. The candidates below are exactly `Bundle.module`'s: one bundle name,
// at the two roots its generated accessor searches. That is what makes
// `isAvailable == true` mean "SwiftMath's lookup will succeed".

public enum MathFonts {

    /// SwiftMath's default font (`MTFontManager.defaultFont` →
    /// `latinModernFont(withSize: 20)`). Asana Math is the documented substitute
    /// — also OpenType MATH, also Latin-Modern-metric-compatible — and is what
    /// `UnicodeMathRenderer` draws with.
    public static let defaultFontName = "latinmodern-math"
    public static let substituteFontName = "Asana-Math"

    /// Directory holding `latinmodern-math.otf` + its `.plist`, resolved on
    /// first use. `nil` means the fonts aren't reachable in this process, which
    /// callers must treat as "no SwiftMath", never as a reason to trap.
    public static let directory: URL? = resolveDirectory()

    /// Whether SwiftMath can render in this process.
    public static var isAvailable: Bool { directory != nil }

    /// The resource-bundle name SwiftPM's generated `Bundle.module` accessor
    /// looks for. SwiftPM derives it from the target that declares the
    /// resources — `SwiftMath_SwiftMath.bundle`. `mathFonts.bundle` is the
    /// directory *inside* that bundle (from `.copy("mathFonts.bundle")`), never
    /// the bundle itself, and accepting that name here is what makes this
    /// file's lookup disagree with SwiftMath's. Issue #14 in one sentence.
    static let resourceBundleName = "SwiftMath_SwiftMath.bundle"

    /// The candidates SwiftMath's own accessor considers, in its order.
    ///
    /// Deliberately short, and the shortness is the point. SwiftPM generates
    /// exactly this code for a target with resources (see swift-package-manager,
    /// `SwiftModuleBuildDescription.generateResourceAccessor`):
    ///
    ///     static let module: Bundle = {
    ///         let mainPath = Bundle.main.bundleURL
    ///             .appendingPathComponent("SwiftMath_SwiftMath.bundle").path
    ///         let buildPath = "<absolute .build path, fixed at compile time>"
    ///         let preferredBundle = Bundle(path: mainPath)
    ///         guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
    ///             Swift.fatalError("could not load resource bundle: from …")
    ///         }
    ///         return bundle
    ///     }()
    ///
    /// So on a shipped app there is one location that matters — the resource
    /// bundle at the *bundle root*, `SwiftMath_SwiftMath.bundle` — and every
    /// extra location this file used to probe (the executable's directory, the
    /// working directory, `.build/<config>`) is a place where this file could
    /// answer "fonts available" while SwiftMath's lookup still reached
    /// `fatalError`. That is not hypothetical: it is how v5.28.1 shipped a
    /// guard that passed and a process that trapped (issue #14).
    ///
    /// The `buildPath` fallback is an absolute path fixed when *SwiftMath* was
    /// compiled, which is the CI machine's `.build` directory — never present
    /// on a user's Mac — so it is not offered here. `Bundle.main.resourceURL`
    /// comes first because that is where an `.appex` (whose `Bundle.main` is
    /// the appex itself) legitimately keeps staged resources, and where the app
    /// copies its own; then the bundle root.
    static func candidates() -> [URL] {
        var roots: [URL] = []
        if let resources = Bundle.main.resourceURL { roots.append(resources) }
        roots.append(Bundle.main.bundleURL)
        return roots.map { $0.appendingPathComponent(resourceBundleName) }
    }

    /// The payload directory, given the candidates SwiftMath's accessor would
    /// consider, in its order. The first usable one wins — so when both layouts
    /// are present (`Contents/Resources`, which Foundation will actually search,
    /// and the flat root, which `swift run` produces) the answer comes from the
    /// same place SwiftMath's lookup will read.
    private static func resolveDirectory() -> URL? {
        for candidate in candidates() {
            if let directory = fontDirectory(in: candidate) { return directory }
        }
        return nil
    }

    /// The payload directory SwiftMath's own lookup resolves to, given the
    /// resource bundle Foundation would open — or `nil` when that lookup cannot
    /// succeed.
    ///
    /// This asks Foundation the same question SwiftMath asks, through the same
    /// call: open the resource bundle, then `url(forResource:"mathFonts",
    /// withExtension:"bundle")`. When it returns a directory, SwiftMath's
    /// `Bundle.module` and its `!`s are known to resolve; when it returns nil,
    /// they would trap, and the renderer must report unavailable instead.
    ///
    /// The subtlety worth naming: adding `Contents/Info.plist` to a resource
    /// bundle makes CoreFoundation classify it as a version-2 Contents bundle,
    /// so `url(forResource:)` searches `Contents/Resources` rather than the
    /// bundle root (`_CFBundleGetBundleVersionForURL` tests `Contents` before
    /// `Resources`, and the first match decides). A payload left only at the
    /// root is then invisible to this call — which is exactly the nil that
    /// `MTFont.fontBundle` force-unwraps. `scripts/build-app.sh` stages the
    /// payload so both layouts resolve; this file just follows Foundation.
    static func fontDirectory(in bundleURL: URL) -> URL? {
        guard let bundle = Bundle(path: bundleURL.path),
              let payload = bundle.url(forResource: "mathFonts", withExtension: "bundle"),
              hasFont(named: defaultFontName, in: payload)
        else { return nil }
        return payload
    }

    /// Whether the resource bundle at `url` is one SwiftMath's lookup can use:
    /// its payload directory resolves. Kept as a named predicate because the
    /// distinction it encodes — "a legal bundle whose payload this lookup finds"
    /// as opposed to "some directory with a `.otf` in it somewhere" — is the
    /// whole of issue #14.
    static func isUsable(bundleAt url: URL) -> Bool {
        fontDirectory(in: url) != nil
    }

    /// A file inside `directory`, tolerating the flat `.copy` layout and the
    /// `mathFonts.bundle/` nesting `.copy("mathFonts.bundle")` reproduces
    /// verbatim (SwiftMath's declaration nests one level deeper than the bundle
    /// name suggests).
    private static func hasFont(named name: String, in directory: URL) -> Bool {
        url(forResource: name, withExtension: "otf", in: directory) != nil
    }

    /// The payload directories under `bundle`, in probe order.
    static func payloadDirectories(in bundle: URL) -> [URL] {
        ["", "mathFonts.bundle"].map {
            $0.isEmpty ? bundle : bundle.appendingPathComponent($0)
        }
    }

    /// A file inside the resolved directory. `nil` when the fonts aren't
    /// reachable — callers must treat that as "no typesetting engine", never as
    /// a reason to trap.
    public static func url(forResource name: String, withExtension ext: String) -> URL? {
        guard let directory else { return nil }
        return url(forResource: name, withExtension: ext, in: directory)
    }

    private static func url(forResource name: String, withExtension ext: String,
                            in directory: URL) -> URL? {
        for root in payloadDirectories(in: directory) {
            let file = root.appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: file.path) { return file }
        }
        return nil
    }

}
