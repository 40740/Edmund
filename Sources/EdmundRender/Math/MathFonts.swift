import AppKit
import SwiftMath

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
// So the app resolves the font directory itself — explicit candidates, no
// `Bundle.module`, no force-unwraps — and treats "fonts unavailable" as a normal
// state: `SwiftMathRenderer` falls back to a Unicode-approximation renderer and
// the editor keeps working with every other part of the document intact.

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
        let fm = FileManager.default
        return fm.fileExists(atPath: directory.appendingPathComponent("\(name).otf").path)
            || fm.fileExists(atPath: directory.appendingPathComponent("Contents/Resources/\(name).otf").path)
            || fm.fileExists(atPath: directory.appendingPathComponent(name).path)   // treat directory itself as payload root
    }

    /// A file inside the resolved directory, tolerating both the flat
    /// (`.copy`) and `Contents/Resources` layouts.
    public static func url(forResource name: String, withExtension ext: String) -> URL? {
        guard let directory else { return nil }
        let flat = directory.appendingPathComponent("\(name).\(ext)")
        if FileManager.default.fileExists(atPath: flat.path) { return flat }
        let nested = directory.appendingPathComponent("Contents/Resources/\(name).\(ext)")
        if FileManager.default.fileExists(atPath: nested.path) { return nested }
        return nil
    }
}
