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
// produces — a bundle with no `Info.plist` of its own.
//
// Foundation's generated `Bundle.module` accessor *traps* (EXC_BREAKPOINT /
// SIGTRAP — not a throwable error) the first time it's touched when it cannot
// resolve its resource bundle, which crashed the extension on the first
// `SyntaxDefinitionStore.reload()` of every Finder Space-bar preview. The
// accessor resolves the bundle by path relative to `Bundle.main.bundleURL`, so
// the bundle has to be at the product root and must not be shaped in a way that
// hides its payload (see `packagingScriptKeepsResourceBundlesFlat`). The store
// additionally refuses to touch `Bundle.module` unless the bundle reports an
// identifier, which is why the packaging gives the syntax bundle one.
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

        // Foundation can build the object, but it has no identifier — the state
        // the store treats as "not safe to reach for Bundle.module" (and the
        // shape the appex used to ship).
        #expect(Bundle(path: fake.path)?.bundleIdentifier == nil,
                "probe bundle should be identifier-less (it has no Info.plist)")

        // Driving the store through its full reload path (bundled lookup + user
        // lookup) must survive that malformed bundle: no trap, defs still load.
        let store = SyntaxDefinitionStore()
        store.reload()
        #expect(!store.availableLanguages().isEmpty)
        #expect(store.availableLanguages().first?.id == "plain")
    }

    @Test("A resource bundle keeps its payload flat — the packaging adds no Contents/")
    func packagingScriptKeepsResourceBundlesFlat() throws {
        // Every SwiftPM resource bundle here holds a `.copy(...)` payload laid
        // out *flat* (at the bundle's own root). Foundation resolves the
        // resources of a bundle that has `Contents/` relative to
        // `Contents/Resources` instead — so giving such a bundle a
        // `Contents/Info.plist` hides its payload from its own `Bundle.module`
        // accessor (`url(forResource:withExtension:)` returns nil). SwiftMath's
        // `MTFont.fontBundle` force-unwraps that lookup, which is how a document
        // with `$…$` started crashing on open: issues #12/#13. The bundle must
        // therefore stay flat, and its identity — which the syntax store needs
        // (issue #8) — goes in a *root* `Info.plist`, which Foundation does read.
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/build-app.sh")
        let text = try String(contentsOf: script, encoding: .utf8)
        #expect(!text.contains("mv \"$bundle/Syntaxes\""),
                "the payload must not be moved — the flat layout is load-bearing")
        #expect(!text.contains("mkdir -p \"$bundle/Contents\""),
                "no resource bundle may be given a Contents/ (it hides the flat payload)")
        #expect(!text.contains("cat > \"$bundle/Contents/Info.plist\""),
                "a resource bundle's identity belongs in a root Info.plist, not Contents/")
        #expect(text.contains("cat > \"$bundle/Info.plist\""),
                "the syntax bundle needs a root Info.plist for its identifier (issue #8)")
        #expect(text.contains("rm -rf \"$bundle/Contents\""),
                """
                the script must also repair a bundle an earlier build left with a \
                Contents/ — `.build` keeps the artifact, so the copy would ship it
                """)
    }

    /// The ordering bug behind "the preview still doesn't work" after v5.24.0:
    /// the script wrote the legal `Info.plist` into the `.build` artifact *after*
    /// `cp -R` had already staged that artifact into the appex — so the appex
    /// shipped the original identifier-less directory and `Bundle.module` kept
    /// trapping. The fix is only real if the copy happens last.
    @Test("The product copies happen after the bundle is given its identity")
    func packagingCopiesAfterMakingBundlesLegal() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/build-app.sh")
        let text = try String(contentsOf: script, encoding: .utf8)

        guard let copyIntoAppex = text.range(of: "cp -R \"$bundle\" \"${APPEX}/\""),
              let copyIntoApp = text.range(of: "cp -R \"$bundle\" \"${BUNDLE}/\""),
              let plistWrite = text.range(of: "cat > \"$bundle/Info.plist\"")
        else {
            Issue.record("could not find the product copies and/or the Info.plist write")
            return
        }
        #expect(plistWrite.lowerBound < copyIntoAppex.lowerBound,
                """
                the appex copy must come *after* the Info.plist is written — \
                copying first ships the identifier-less bundle that Bundle.module \
                traps on (this is the bug that survived v5.24.0)
                """)
        #expect(plistWrite.lowerBound < copyIntoApp.lowerBound,
                "the app copy must come after the bundle is given its identity too")
    }

    /// `codesign` refuses to seal a bundle with extra items at its root
    /// ("unsealed contents present in the bundle root"), and the generated
    /// accessor looks for the resource bundles at `Bundle.main.bundleURL` — the
    /// `.appex` root for a preview process (not `Contents/Resources`, which is
    /// `resourceURL`). So the copies have to land after the signature. Before
    /// v5.30.0 they landed inside `Contents/Resources`, where a preview needed
    /// them to be *both* in the wrong place and the wrong shape: the extension
    /// reached SwiftMath for any document with math.
    @Test("The appex receives its resource bundles after it is signed")
    func appexResourceBundlesArriveAfterSigning() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/build-app.sh")
        let text = try String(contentsOf: script, encoding: .utf8)
        guard let appexSign = text.range(
                of: "codesign --force --sign - --identifier \"com.i7t5.edmund.quicklook\""),
              let appexCopy = text.range(of: "cp -R \"$bundle\" \"${APPEX}/\"")
        else {
            Issue.record("could not locate the appex signing step and/or its bundle copy")
            return
        }
        #expect(appexSign.lowerBound < appexCopy.lowerBound,
                "codesign cannot seal a root that already holds the bundles — copy after signing")
        #expect(!text.contains("\"${APPEX}/Contents/Resources/\"\n"),
                """
                the appex's bundles belong at the .appex root: that is where \
                Bundle.main.bundleURL points for an extension, so Contents/Resources \
                leaves them unfindable and the preview traps on the first equation
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

    @Test("The packaging script gives every resource bundle an identity, flat and root")
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
        #expect(text.contains("CFBundleIdentifier"),
                "the generated plist must declare an identifier (the store wants one)")
        #expect(text.contains("CFBundlePackageType"),
                "the generated plist must declare a package type")
        #expect(!text.contains("Contents/Resources/Syntaxes"),
                "the payload is not duplicated under Contents/Resources — that layout is what hid the fonts")
        #expect(text.contains("SwiftMath_*"),
                "the font bundle is called out by name: it must not be given a plist at all")
    }

    /// The assertion that makes the whole rule unignorable: the packaging script
    /// has to *prove* the layout it produced, and fail the build when it is
    /// wrong. `.build` artifacts survive between runs (an earlier build of this
    /// same script left the crashing `Contents/` in them), so "the script writes
    /// the right thing" is not the same as "the product contains it".
    @Test("The build verifies the resource-bundle layout it produced")
    func buildVerifiesResourceBundleLayout() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("scripts/build-app.sh"),
                             encoding: .utf8)
        #expect(text.contains("verify-app-bundle.sh"),
                "build-app.sh must run the layout verifier, or a regression ships silently")

        // The verifier has to ask Foundation the same question SwiftMath asks,
        // not merely list directories: both the crashing and the fixed layout
        // contain the same files.
        let probe = try String(contentsOf: root.appendingPathComponent("scripts/verify-app-bundle.swift"),
                               encoding: .utf8)
        #expect(probe.contains("forResource: \"mathFonts\", withExtension: \"bundle\""),
                "the probe must replay MTFont.fontBundle's lookup")
        #expect(probe.contains("Bundle(url: fonts)"),
                "the probe must replay MTFont.fontBundle's second force-unwrap")
        #expect(probe.contains("bundleIdentifier != nil"),
                "the probe must check the syntax bundle's identity too (issue #8)")
        #expect(probe.contains("EdmundQuickLook.appex"),
                """
                the preview runs the same pipeline behind Bundle.main = the .appex, \
                so its root has to be verified as well
                """)
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
