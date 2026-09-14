import Foundation

// MARK: - PulseFonts
//
// Make the bundle we resolved the one SwiftMath's `Bundle.module` accessor finds.
//
// SwiftMath asks for its fonts through the accessor Foundation generates per
// package, whose Darwin body is, in shape:
//
//   static let module = { Bundle(for: BundleFinder.self).resourceURL
//                         ?? Bundle.main.resourceURL
//                         ?? Bundle.main.bundleURL }()
//
// The `Bundle(for:)` step is the one that fails for a SwiftPM dependency's
// resource bundle, and in the generated accessor failing is not `nil` — it is a
// trap. Every fallback after it is a *main* bundle, though, so the way in is to
// make the fonts' bundle the main one.
//
// CoreFoundation builds the main bundle from the *process path*:
//
//   CFBundleGetMainBundle → _CFBundleGetMainBundleAlreadyLocked
//                         → _CFProcessPath()      // reads $CFProcessPath on macOS
//                         → _CFBundleCopyBundleURLForExecutableURL
//                         → _CFBundleCreate(…, bundleURL, true, false)
//
// `_CFProcessPath()` returns `$CFProcessPath` when it is set (`CFPlatform.c`,
// guarded by `DEPLOYMENT_TARGET_MACOSX` and `!issetugid()`), and otherwise falls
// back to the real executable — which is what makes the variable a supported
// lever rather than a hack around one. So: point `CFProcessPath` at the fonts'
// bundle's executable, then ask CoreFoundation for the main bundle, and read
// back what Foundation reports.
//
// Two things this deliberately does *not* do. It doesn't call any `_CFBundle…`
// *query* — on Darwin those are Swift-mangled names (`__CFBundleGetMainBundle`)
// and declaring them by symbol fails to link, which is why the check below goes
// through the public `CFBundleGetMainBundle()`. And it doesn't hand the bundle
// to `_CFBundleCreate` blind: the argument must *be* the fonts' bundle — with the
// `CFBundleIdentifier` `build-app.sh` writes into it — or the read-back is the
// only thing that would notice a wrong one.

/// CoreFoundation SPIs this needs, declared by symbol. Both are exported by CF
/// and declared in its private headers — real linkable symbols. The main-bundle
/// *query* is the public `CFBundleGetMainBundle()`, because the `_`-prefixed
/// variant is a Swift-mangled name on Darwin (`__CFBundleGetMainBundle`) and
/// does not link.
@_silgen_name("_CFBundleCopyBundleURLForExecutableURL")
private func _CFBundleCopyBundleURLForExecutableURL(_ url: CFURL) -> Unmanaged<CFURL>?

@_silgen_name("_CFBundleCreateIfLooksLikeBundle")
private func _CFBundleCreateIfLooksLikeBundle(_ allocator: CFAllocator?,
                                              _ url: CFURL) -> Unmanaged<CFBundle>?

enum PulseFonts {

    /// Publish `bundle` as the process's main bundle.
    ///
    /// The read-back is the check, not decoration: `Bundle.main.bundleURL` is the
    /// same value the generated accessor's fallbacks consult, so "it changed to
    /// the bundle we asked for" is precisely "SwiftMath will find its fonts".
    @discardableResult
    static func publish(_ bundle: Bundle) -> Bool {
        // 1. The lever CoreFoundation reads first. Set before anything has asked
        //    for the main bundle — `MathFonts.prepare()` runs from `main`, ahead
        //    of the document and the app's own `Bundle.main` uses.
        setenv("CFProcessPath", executablePath(inside: bundle), 1)

        // 2. Ask again, and check. `_CFBundleCreateIfLooksLikeBundle` is
        //    CFBundleCreate-with-a-check; either call builds and caches the
        //    bundle the accessor will later be handed.
        // `CFBundleGetIdentifier` returns an already-managed `CFString?`, so it
        // bridges straight to `String?` — no manual retain bookkeeping.
        // `CFBundleGetMainBundle` is the public query, and it is already a
        // Swift-imported `CFBundle?` — the `_`-prefixed spelling is a
        // Swift-mangled name on Darwin and does not link.
        if let main = CFBundleGetMainBundle(),
           let identifier = CFBundleGetIdentifier(main) as String?,
           identifier == bundle.bundleIdentifier {
            return true
        }
        if let url = CFURLCreateWithFileSystemPath(nil, bundle.bundleURL.path as CFString,
                                                  .cfurlposixPathStyle, true) {
            _ = _CFBundleCreateIfLooksLikeBundle(nil, url)
        }
        return Bundle.main.bundleURL == bundle.bundleURL
    }

    /// The file CoreFoundation should treat as the process. It only uses the path
    /// to *find the bundle* (`_CFBundleCopyBundleURLForExecutableURL`), so any
    /// existing file inside the bundle works; the bundle's own executable is the
    /// honest choice when it has one.
    private static func executablePath(inside bundle: Bundle) -> String {
        let executable = bundle.executableURL?.path
        if let executable, !executable.isEmpty { return executable }
        // A resource bundle has no executable: point at something of its own so
        // the bundle URL is derived as its container, not as ours.
        return bundle.bundleURL.appendingPathComponent("Contents/Info.plist").path
    }
}
