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
