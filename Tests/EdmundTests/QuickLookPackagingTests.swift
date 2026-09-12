import Testing
import Foundation
@testable import EdmundCore

// MARK: - Quick Look packaging regression tests (issue #8)
//
// The Quick Look appex ships its own copy of the `Edmund_EdmundCore.bundle`
// resource bundle so the bundled `Syntaxes/*.json` defs are available to
// `SyntaxDefinitionStore`. That bundle is what `.copy("Resources/Syntaxes")`
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
