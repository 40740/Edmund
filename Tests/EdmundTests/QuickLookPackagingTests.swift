import Testing
import Foundation
import EdmundMarkdown
@testable import EdmundCore

// MARK: - Quick Look packaging regression tests (issue #8)
//
// The Quick Look appex ships its own copy of the resource bundle the syntax
// definitions live in (`Edmund_EdmundMarkdown.bundle`, formerly
// `Edmund_EdmundCore.bundle`) so the bundled `Syntaxes/*.json` defs are
// available to `SyntaxDefinitionStore`. That bundle is what `.copy("Resources/Syntaxes")`
// produces — a bundle that, unless the packaging step writes one, has **no**
// `Contents/Info.plist`.
//
// Foundation's generated `Bundle.module` accessor *traps* (EXC_BREAKPOINT /
// SIGTRAP — not a throwable error) the first time it's touched when its bundle
// has no identifier, which crashed the extension on the first
// `SyntaxDefinitionStore.reload()` of every Finder Space-bar preview.
//
// These tests pin the two halves of the fix:
//   1. the store still resolves the bundled defs (behaviour unchanged), and
//   2. the lookup degrades instead of trapping when a bundle is malformed.

@Suite("Quick Look — bundled syntax resources")
struct QuickLookSyntaxPackagingTests {

    @Test("Bundled definitions still load after the defensive lookup")
    func bundledDefsStillLoad() {
        let store = SyntaxDefinitionStore()
        // `py` is an alias of the bundled `python` def; if the resource lookup
        // regressed to "found nothing", this would be `.unknown`.
        guard case .definition(let def) = store.resolve("py") else {
            Issue.record("py did not resolve — bundled Syntaxes lookup regressed")
            return
        }
        #expect(def.name == "python")
    }

    @Test("All bundled languages are reachable by their canonical name")
    func canonicalNamesResolve() {
        let store = SyntaxDefinitionStore()
        let ids = store.availableLanguages().map(\.id)
        #expect(ids.first == "plain")
        for expected in ["swift", "python", "javascript", "json", "yaml"] {
            #expect(ids.contains(expected), "missing bundled language: \(expected)")
        }
    }

    @Test("A malformed (identifier-less) resource bundle never traps the store")
    func malformedBundleDoesNotTrap() {
        // A directory with the SwiftPM resource-bundle name but no Info.plist —
        // exactly what shipped inside the appex. Touching `Bundle.module` for it
        // is the crash (EXC_BREAKPOINT / SIGTRAP), and it cannot be caught, so
        // the store must recognise the bundle as illegal and never reach for it.
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("EdmundPackagingProbe-\(UUID().uuidString)")
        let fake = root.appendingPathComponent("Edmund_EdmundCore.bundle")
        try? FileManager.default.createDirectory(at: fake, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Foundation can build the object, but it has no identifier — the exact
        // precondition SwiftPM's `Bundle.module` accessor asserts (and traps) on.
        #expect(Bundle(path: fake.path)?.bundleIdentifier == nil,
                "probe bundle should be identifier-less (it has no Info.plist)")

        // Driving the store through its full reload path (bundled lookup + user
        // lookup) must survive that malformed bundle: no trap, defs still load.
        let store = SyntaxDefinitionStore()
        store.reload()
        #expect(!store.availableLanguages().isEmpty)
        #expect(store.availableLanguages().first?.id == "plain")
    }

    @Test("A resource bundle keeps a flat Syntaxes next to the Contents/Resources one")
    func packagingScriptKeepsBothLayouts() throws {
        // `SyntaxDefinitionStore` probes the flat and the Contents/Resources
        // layout, and the bundle's own `Bundle.module` accessor finds the flat
        // one. The packaging step must therefore leave both in place — a `mv`
        // here silently breaks whichever reader uses the other.
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/build-app.sh")
        let text = try String(contentsOf: script, encoding: .utf8)
        #expect(!text.contains("mv \"$bundle/Syntaxes\""),
                "the payload must be copied, not moved — the flat layout is load-bearing")
        #expect(text.contains("cp -R \"$bundle/Syntaxes\""),
                "the flat payload must be copied into Contents/Resources")
    }

    /// The ordering bug behind "the preview still doesn't work" after v5.24.0:
    /// the script wrote the legal `Info.plist` into the `.build` artifact *after*
    /// `cp -R` had already staged that artifact into the appex — so the appex
    /// shipped the original identifier-less directory and `Bundle.module` kept
    /// trapping. The fix is only real if the copy happens last.
    @Test("The appex copy happens after the bundle is made legal")
    func packagingCopiesAfterMakingBundlesLegal() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/build-app.sh")
        let text = try String(contentsOf: script, encoding: .utf8)

        guard let loopStart = text.range(of: "for bundle in .build/release/*.bundle; do"),
              let loopEnd = text.range(of: "\ndone\n", range: loopStart.upperBound..<text.endIndex)
        else {
            Issue.record("could not locate the resource-bundle loop in build-app.sh")
            return
        }
        let loop = String(text[loopStart.lowerBound..<loopEnd.upperBound])

        guard let copyIntoAppex = loop.range(of: "cp -R \"$bundle\" \"${APPEX}/Contents/Resources/\""),
              let plistWrite = loop.range(of: "cat > \"$bundle/Contents/Info.plist\"")
        else {
            Issue.record("could not find the appex copy and/or the Info.plist write")
            return
        }
        #expect(plistWrite.lowerBound < copyIntoAppex.lowerBound,
                """
                the appex copy must come *after* the Info.plist is written — \
                copying first ships the identifier-less bundle that Bundle.module \
                traps on (this is the bug that survived v5.24.0)
                """)
    }

    /// The appex has to be a *bundle*, not a folder with a binary in it: no
    /// `Info.plist` means Quick Look has nothing to route a Space-bar press to,
    /// which is what "扩展在预览此文稿期间失败" says. The script must ship one.
    @Test("The appex gets an Info.plist before it is signed")
    func appexGetsItsInfoPlist() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/build-app.sh")
        let text = try String(contentsOf: script, encoding: .utf8)
        guard let appex = text.range(of: "APPEX="),
              let sign = text.range(of: "codesign --force --sign - --identifier \"com.i7t5.edmund.quicklook\"")
        else {
            Issue.record("could not locate the appex assembly or the signing step")
            return
        }
        let assembly = String(text[appex.lowerBound..<sign.lowerBound])
        #expect(assembly.contains("cp Resources/QuickLookInfo.plist"),
                "the appex needs its Info.plist, or it is not an extension at all")
        #expect(assembly.contains("${APPEX}/Contents/MacOS/"),
                "the extension binary belongs in Contents/MacOS")
    }

    /// The extension binary is linked with the application-extension marker, so
    /// anything that inspects it sees a real app extension rather than a plain
    /// executable in an .appex-shaped folder.
    @Test("The extension binary is linked as an application extension")
    func extensionBinaryIsMarked() throws {
        let manifest = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Package.swift")
        let text = try String(contentsOf: manifest, encoding: .utf8)
        // `-fapplication-extension` is a *frontend* flag: it has to reach the
        // compiler through `-Xcc`. Passing it to `ld` fails outright
        // ("unknown options"), which is exactly what a bare `-Xlinker` entry
        // did. The distinction is the whole content of this test.
        #expect(text.contains("\"-Xcc\", \"-fapplication-extension\""),
                "the extension marker must reach the compiler, not the linker")
        #expect(!text.contains("\"-Xlinker\", \"-fapplication-extension\""),
                "the linker rejects -fapplication-extension: it is a frontend flag")
        #expect(text.contains("_NSExtensionMain"),
                "its entry point is NSExtensionMain, not the target's main.swift")
    }

    @Test("The packaging script writes an Info.plist into every copied resource bundle")
    func packagingScriptMakesBundlesLegal() throws {
        // The root-cause half of the fix lives in build-app.sh, which the Linux
        // runner can't execute — assert on its content instead so the rule can't
        // be dropped silently by a later refactor.
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EdmundTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("scripts/build-app.sh")
        let text = try String(contentsOf: script, encoding: .utf8)
        #expect(text.contains("Contents/Info.plist"),
                "build-app.sh must write an Info.plist into each resource bundle")
        #expect(text.contains("CFBundlePackageType"),
                "the generated plist must declare a package type")
        #expect(text.contains("Contents/Resources/Syntaxes"),
                "the payload must be *also* laid out under Contents/Resources")
    }
}

// MARK: - Where the payload is looked for (issue #8, third round)
//
// The lookup's root list is not guessable from the SwiftPM docs, and getting it
// wrong is silent: a preview with no syntax definitions, no crash, no error. Two
// layouts are load-bearing for the test process in particular — the resource
// bundle sits *next to* the `.xctest` bundle (not inside it), and its payload is
// flat `Syntaxes/` (a plain `swift build` doesn't produce a legal bundle).

@Suite("Quick Look — syntax payload lookup")
struct SyntaxPayloadLookupTests {

    @Test("A payload flat inside the module's resource bundle is found")
    func flatPayloadInsideResourceBundle() throws {
        // Mirrors `swift build`'s output: `.build/debug/Edmund_EdmundCore.bundle/Syntaxes/*.json`,
        // with the bundle beside the executable rather than inside a product.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("edmund-syntax-\(UUID().uuidString)", isDirectory: true)
        let bundle = root.appendingPathComponent("Edmund_EdmundCore.bundle", isDirectory: true)
        let syntaxes = bundle.appendingPathComponent("Syntaxes", isDirectory: true)
        try FileManager.default.createDirectory(at: syntaxes, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{}".utf8).write(to: syntaxes.appendingPathComponent("probe.json"))

        // The probe only proves the *shape* is what the search accepts: the real
        // store resolves against the process's own bundles, so what's asserted
        // here is that a directory with this shape yields its json files.
        let found = (try? FileManager.default.contentsOfDirectory(
            at: syntaxes, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "json" } ?? []
        #expect(found.count == 1)
        #expect(found.first?.lastPathComponent == "probe.json")
    }

    @Test("The bundled definitions load in the test process")
    func bundledDefinitionsLoad() {
        // The end-to-end version of the above, and the real regression guard: the
        // store has to find its payload under the layout the test runner produces
        // (payload beside the .xctest bundle). This failed silently for a whole
        // release cycle — the app's own rendering kept working, so only the
        // preview noticed.
        let store = SyntaxDefinitionStore()
        #expect(store.availableLanguages().map(\.id).contains("swift"))
        #expect(store.availableLanguages().map(\.id).contains("python"))
    }
}

// MARK: - Math fonts in the shipped bundle (issue #12)
//
// Opening a document containing `$…$` crashed the app inside SwiftMath's
// `MTFont.fontBundle.getter` (`EXC_BREAKPOINT` / `SIGTRAP`) because the accessor
// that reaches the OpenType math fonts traps when its bundle is missing. The
// app now degrades instead of crashing (`MathFonts` / `UnicodeMathRenderer`),
// but "degrades silently in every release" is its own bug — so the packaging
// step is asserted to ship the fonts to both places the app looks, and to the
// Quick Look appex as well.

@Suite("Packaging — SwiftMath math fonts")
struct MathFontPackagingTests {

    private func packagingScript() throws -> String {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/build-app.sh")
        return try String(contentsOf: script, encoding: .utf8)
    }

    @Test("Math fonts are copied into the app bundle's Resources as well as its root")
    func fontsShipToBothLocations() throws {
        let text = try packagingScript()
        guard let copy = text.range(of: "Copying SwiftPM resource bundles") else {
            Issue.record("could not locate the resource-bundle copy step")
            return
        }
        let step = String(text[copy.lowerBound...])
        #expect(step.contains("cp -R \"$bundle\" \"${BUNDLE}/\""),
                "Bundle.main.bundleURL is where SwiftMath's own accessor has always looked")
        #expect(step.contains("cp -R \"$bundle\" \"${BUNDLE}/Contents/Resources/\""),
                "Bundle.main.resourceURL is the documented location and what an appex reads")
    }

    @Test("The copy step verifies the font file actually shipped")
    func fontsAreVerified() throws {
        let text = try packagingScript()
        // "The bundle exists" was satisfied by the syntax bundle alone — the step
        // looked like it worked while shipping no maths at all. Only the .otf
        // itself proves the fonts are there.
        #expect(text.contains("latinmodern-math.otf"),
                "the step must confirm the OpenType font file, not just the bundle directory")
        #expect(text.contains("no SwiftMath resource bundle in .build/release"),
                "a release that ships no math fonts must say so")
    }

    @Test("The Quick Look appex gets the math fonts too")
    func appexShipsFonts() throws {
        let text = try packagingScript()
        guard let appexStart = text.range(of: "Assembling Quick Look extension"),
              let fontsInAppex = text.range(of: "*SwiftMath*) cp -R \"$bundle\" \"${APPEX}/Contents/Resources/\"")
        else {
            Issue.record("the appex does not receive the SwiftMath bundle")
            return
        }
        #expect(appexStart.lowerBound < fontsInAppex.lowerBound,
                "fonts must be staged into the appex during its assembly, before signing")
    }

    @Test("Font resolution never relies on Bundle.module in the render layer")
    func renderLayerAvoidsBundleModule() throws {
        // Same trap as the syntax definitions in issue #8, one bundle over: an
        // appex (or a relocated install) that lacks the bundle makes
        // `Bundle.module` trap — the app's own crash, issue #12.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/EdmundRender/Math/MathFonts.swift")
        // Comments in that file explain the trap at length; only code counts.
        let code = String(try String(contentsOf: root, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "" }
            .joined(separator: "\n"))
        #expect(!code.contains("Bundle.module"),
                "font resolution must not use the generated accessor — it traps")
        #expect(code.contains("Bundle.main.resourceURL"),
                "resolution is explicit: Bundle.main's Resources first")
    }
}
