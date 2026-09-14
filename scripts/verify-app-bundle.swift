// Build-time assertion: the resource bundles in the built product are where the
// generated `Bundle.module` accessors will look for them, in the shape those
// accessors can read.
//
// Why this exists as an executable probe instead of a `ls` in the packaging
// script: the failure it guards against has *no* structural signature at the
// level a shell test can see. `SwiftMath_SwiftMath.bundle` built by v5.27.0 and
// its fix differ only by the presence of `Contents/` — both look like a bundle,
// both contain `mathFonts.bundle/mathfonts/x.otf`, and `codesign`, `find` and
// `du` are equally happy with either. What differs is what Foundation answers,
// and that answer is only observable by asking Foundation. The questions below
// are the ones SwiftMath's own code asks, in order:
//
//   MTFont.fontBundle      = Bundle(url: Bundle.module.url(forResource: "mathFonts",
//                                                          withExtension: "bundle")!)!
//   MTFont.init(fontWithName:) = bundle.path(forResource: name, ofType: "otf")   // force-unwrapped
//                                bundle.url(forResource: name, withExtension: "plist")  // force-unwrapped
//
// `name` is SwiftMath's default font, the one `MTMathImage(latex:…)` — the only
// entry point Edmund's renderer uses — resolves through `MTFontManager`.
//
// The syntax bundle is checked too (issue #8): `SyntaxDefinitionStore` reaches
// for `Bundle.module` only when the bundle reports an identifier, and a bundle
// without one used to make that accessor trap.
//
// Usage: swift scripts/verify-app-bundle.swift build/Edmund.app
// Exits 0 when every product root is good, 1 with a report otherwise.

import Foundation

let mathBundleName = "SwiftMath_SwiftMath.bundle"
let syntaxBundleName = "Edmund_EdmundMarkdown.bundle"
let mathPayload = "mathFonts.bundle"
let defaultFont = "latinmodern-math"

var failures: [String] = []

/// One line of output per check, only ever printed when it fails.
func check(_ description: String, _ condition: Bool, detail: @autoclosure () -> String = "") {
    if condition {
        print("  ok  \(description)")
    } else {
        let extra = detail()
        print("  FAIL \(description)\(extra.isEmpty ? "" : " — \(extra)")")
        failures.append(description)
    }
}

/// Replay the SwiftMath lookups from `productRoot` — the `.app` root, and
/// separately the `.appex` root, because the accessor resolves against
/// `Bundle.main.bundleURL` and in a preview process that is the extension.
func verifyMathBundle(at productRoot: URL, label: String) {
    let bundlePath = productRoot.appendingPathComponent(mathBundleName).path
    print("\n\(label): \(mathBundleName)")

    check("bundle exists at the product root", FileManager.default.fileExists(atPath: bundlePath),
          detail: bundlePath)
    guard let bundle = Bundle(path: bundlePath) else {
        check("Bundle(path:) resolves it (the accessor's preferredBundle)", false, detail: bundlePath)
        return
    }
    check("Bundle(path:) resolves it (the accessor's preferredBundle)", true)

    check("no Contents/ inside the bundle (Contents/ makes Foundation resolve "
          + "resources relative to Contents/Resources, where a .copy(...) payload is not)",
          !FileManager.default.fileExists(atPath: bundlePath + "/Contents"),
          detail: "Contents/ present — url(forResource:) below returns nil for the flat payload")

    let fonts = bundle.url(forResource: "mathFonts", withExtension: "bundle")
    check("url(forResource: \"mathFonts\", withExtension: \"bundle\") != nil "
          + "(where MTFont.fontBundle's force-unwrap traps)", fonts != nil)
    guard let fonts, let fontBundle = Bundle(url: fonts) else {
        check("Bundle(url:) resolves the fonts bundle (MTFont's second force-unwrap)", false)
        return
    }
    check("Bundle(url:) resolves the fonts bundle (MTFont's second force-unwrap)", true)

    let otf = fontBundle.path(forResource: defaultFont, ofType: "otf")
    check("default font \"\(defaultFont).otf\" resolves through it", otf != nil)
    let plist = fontBundle.url(forResource: defaultFont, withExtension: "plist")
    check("its math table \"\(defaultFont).plist\" resolves through it", plist != nil)
    for path in [otf, plist?.path].compactMap({ $0 }) {
        check("payload is a real file: \((path as NSString).lastPathComponent)",
              FileManager.default.fileExists(atPath: path), detail: path)
    }
}

/// Issue #8: the syntax definitions travel in their own resource bundle, and the
/// store only trusts it when it has an identity.
func verifySyntaxBundle(at productRoot: URL, label: String) {
    let bundlePath = productRoot.appendingPathComponent(syntaxBundleName).path
    print("\n\(label): \(syntaxBundleName)")

    check("bundle exists at the product root", FileManager.default.fileExists(atPath: bundlePath),
          detail: bundlePath)
    guard let bundle = Bundle(path: bundlePath) else {
        check("Bundle(path:) resolves it", false, detail: bundlePath)
        return
    }
    check("Bundle(path:) resolves it", true)
    check("it has a bundle identifier (the store skips Bundle.module without one)",
          bundle.bundleIdentifier != nil,
          detail: "bundleIdentifier == nil — write a root Info.plist with CFBundleIdentifier")
    check("no Contents/ inside the bundle", !FileManager.default.fileExists(atPath: bundlePath + "/Contents"))

    let syntaxes = bundle.bundleURL.appendingPathComponent("Syntaxes", isDirectory: true)
    let defs = (try? FileManager.default.contentsOfDirectory(at: syntaxes, includingPropertiesForKeys: nil))?
        .filter { $0.pathExtension.lowercased() == "json" } ?? []
    check("the flat Syntaxes/ payload is there (\(defs.count) definitions)", !defs.isEmpty,
          detail: syntaxes.path)
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift verify-app-bundle.swift <path/to/Edmund.app>\n".utf8))
    exit(2)
}
let app = URL(fileURLWithPath: CommandLine.arguments[1])
let appex = app.appendingPathComponent("Contents/PlugIns/EdmundQuickLook.appex")

print("Verifying resource-bundle layout in \(app.path)")
verifyMathBundle(at: app, label: "app root")
verifySyntaxBundle(at: app, label: "app root")
verifyMathBundle(at: appex, label: "appex root")
verifySyntaxBundle(at: appex, label: "appex root")

if failures.isEmpty {
    print("\nResource bundles verified: \(failures.count) failures.")
    exit(0)
}
print("\n\(failures.count) resource-bundle check(s) failed — the app would crash "
      + "(EXC_BREAKPOINT / SIGTRAP) the moment it rendered LaTeX.")
exit(1)
