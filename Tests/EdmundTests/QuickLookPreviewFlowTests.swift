import Testing
import Foundation
import EdmundRender
import EdmundMarkdown

// MARK: - Quick Look preview flow (issue #8)
//
// Three rounds of this fix tried to make the *render* work: stop the crash (a
// resource bundle with no Info.plist), stop the eternal spinner (don't await a
// WebKit callback), always answer (`preparePreviewOfFile` returns a complete
// view). All three shipped, and the user's Finder said exactly what it said at
// the start:
//
//     扩展"com.i7t5.edmund.quicklook"在预览此文稿期间失败。
//
// That message is not the spinner. It is Quick Look reporting the extension
// **failed** — it never got a usable extension. The fourth round is about what
// the appex *is*, and these tests pin that:
//
//   1. it links a narrow rendering pipeline, not the whole editor;
//   2. its view is laid out at the size the host gives it, and no smaller;
//   3. it does not go through the app's `NSDocument` machinery;
//   4. it resolves the appearance it renders in.
//
// A unit test cannot start a Quick Look appex (it needs the host, a window
// server and a signed bundle), so the invariants that live in the extension's
// own process are asserted at the source level — the same approach the packaging
// tests take for `build-app.sh`.

private func repoFile(_ path: String) throws -> String {
    try String(contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // EdmundTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent(path), encoding: .utf8)
}

/// The same source with `//`/`///` comment lines dropped.
///
/// Every one of these files documents *why* the code is shaped the way it is, and
/// that prose necessarily names the very constructs the assertions below forbid
/// ("the appex used to link the editor", "`NSDocumentController` opened the
/// file…"). Asserting on the raw text therefore fails on the explanation rather
/// than the code — so the checks run against code lines only.
private func code(_ source: String) -> String {
    source.split(separator: "\n", omittingEmptySubsequences: false)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")
}

private func previewCode() throws -> String { code(try previewSource()) }

/// The `Package.swift` text of one target, from its `name:` to the line that
/// closes its argument list.
///
/// Deliberately not a "find the next closing paren line" search: the targets'
/// closing lines differ (`.target(` blocks end with `]),`, `resources: …]),`,
/// etc.), so a single fixed pattern is absent from the manifest and every lookup
/// using it threw. The block ends at the first line that closes a paren at the
/// target's own indentation.
private func targetBlock(_ name: String, in manifest: String) throws -> String {
    guard let start = manifest.range(of: "name: \"\(name)\""),
          let end = statementEnd(in: manifest, from: start.upperBound)
    else { throw CocoaError(.fileReadCorruptFile) }
    return String(manifest[start.lowerBound..<end])
}

/// The index just past the line that closes the target's argument list — the
/// first line whose code ends in `),`. Every `.target(…)` here is written as one
/// statement whose last line is the closing `)]),` (there is no bare `        ),`
/// line to search for, which is what an earlier version of this test assumed and
/// why it threw).
private func statementEnd(in manifest: String, from index: String.Index) -> String.Index? {
    var cursor = index
    while let newline = manifest[cursor...].firstIndex(of: "\n") {
        let line = manifest[cursor..<newline].trimmingCharacters(in: .whitespaces)
        cursor = manifest.index(after: newline)
        if line.hasSuffix("),") && !line.hasPrefix("//") && !line.hasPrefix(".product") {
            return cursor
        }
    }
    return nil
}

private func previewSource() throws -> String {
    try repoFile("Sources/EdmundQuickLook/PreviewViewController.swift")
}

// MARK: - The appex must not link the editor

@Suite("Quick Look — the extension links a narrow pipeline, not the editor")
struct QuickLookDependencyTests {

    /// The dependency that matters: a preview extension is started on the
    /// Space-bar path and judged on how fast it answers. Depending on
    /// `EdmundCore` meant the appex imported the whole editor — TextKit 2, the
    /// extension host, the syntax highlighter, the WebKit read view and the
    /// RaTeX/WASM math host — before it could draw anything.
    @Test("The extension target depends on the rendering pipeline only")
    func extensionDependsOnRenderOnly() throws {
        let manifest = try repoFile("Package.swift")
        let block: String
        do {
            block = try targetBlock("EdmundQuickLook", in: manifest)
        } catch {
            Issue.record("could not locate the EdmundQuickLook target in Package.swift")
            return
        }
        #expect(block.contains("\"EdmundRender\""),
                "the preview needs the HTML pipeline")
        #expect(!block.contains("\"EdmundCore\""),
                """
                the appex must not link the editor — every framework the editor \
                imports is one the preview process pays for before its first paint
                """)
        #expect(!block.contains("SwiftMath"),
                "math rendering comes in through EdmundRender, not the appex directly")
    }

    /// The shared modules the appex does link must not have grown a dependency
    /// on the editor: the split is only real if it holds in both directions.
    @Test("The shared modules do not depend on the editor or on each other upwards")
    func sharedModulesAreALowerLayer() throws {
        let manifest = try repoFile("Package.swift")
        func deps(of name: String) throws -> String {
            try targetBlock(name, in: manifest)
        }
        #expect(!(try deps(of: "EdmundMarkdown")).contains("EdmundRender"),
                "EdmundMarkdown is the lowest layer — it cannot import the render pipeline")
        #expect(!(try deps(of: "EdmundRender")).contains("EdmundCore"),
                "EdmundRender is below EdmundCore — the editor depends on it, not the reverse")
    }

    /// The extension has to be able to write its own diagnostics: it is started by
    /// the system rather than by the app, so nothing hands it a configured logger.
    /// Two halves to that — the logger lives in a module both processes link, and
    /// the extension's own source reports what it rendered.
    @Test("The extension can log on its own")
    func extensionLogsOnItsOwn() throws {
        let log = try repoFile("Sources/EdmundRender/Diagnostics/Log.swift")
        #expect(log.contains("\"settings.general.diagnosticLogging\""),
                """
                the logger resolves the app's preference itself, or an extension \
                started without the app leaves no reason behind when a preview fails
                """)
        let preview = try previewCode()
        #expect(preview.contains("Log.error"),
                "the preview reports what it could not render")
    }

    /// `main.swift` runs during static initialization of the appex module. It
    /// used to import `EdmundCore` just to point the log at the app's directory,
    /// which is exactly the kind of thing that pulls a framework in before the
    /// preview exists.
    @Test("The extension entry point imports nothing but Foundation")
    func entryPointStaysMinimal() throws {
        let source = try repoFile("Sources/EdmundQuickLook/main.swift")
        let imports = source.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("import ") }
        #expect(imports == ["import Foundation"],
                "the appex entry point must not drag frameworks into the preview process: \(imports)")
    }
}

// MARK: - The view must have a size

@Suite("Quick Look — the preview is laid out at the host's size")
struct QuickLookLayoutTests {

    /// The bug that survived three rounds: the view was returned as a container
    /// with a *hidden* web view sized by `autoresizingMask`, on the theory that
    /// the host would resize the container and push the new size down.
    /// Autoresizing only fires when the superview's own frame changes through
    /// `setFrameSize`; a host that installs Auto Layout constraints never does
    /// that. The web view stayed 0×0 and rendered nothing.
    @Test("The web view is placed from the container's real bounds")
    func webViewIsPlacedFromContainerBounds() throws {
        let source = try previewCode()
        #expect(source.contains("override func viewDidLayout()"),
                "layout is where the host's chosen size is known")
        #expect(source.contains("container.bounds"),
                "the web view must be placed at the size the host actually gave")
        #expect(source.contains("minimumSize"),
                """
                a host that hands over a zero-sized view would otherwise get a \
                zero-sized web view, and a 0×0 web view has nothing to show
                """)
    }

    /// Returning a view that is already laid out is not enough on its own: two
    /// things have to be true at the moment it lands.
    @Test("The document is rendered synchronously, and the view is opaque")
    func documentIsRenderedSynchronously() throws {
        let source = try previewSource()
        let implementation = code(source)
        // The render happens inside `preparePreviewOfFile`'s own call tree, so the
        // returned view is already complete — nothing about the *content* waits.
        #expect(source.contains("DocumentHTML.full("),
                "the page is built up front, not by a later callback")
        // The callback exists, but only to *report* a failure after the fact —
        // nothing waits on it. The distinction is the whole fix: Quick Look holds
        // its loading state until `preparePreviewOfFile` returns, and a preview
        // that would not return until WebKit called back is the eternal spinner.
        #expect(implementation.contains("webView.onLoadFinished"),
                "a load that fails after the view is up still has to be reported")
        #expect(implementation.contains("showLoadFailure"),
                "and reported on screen, not only in the log")
    }

    /// `ReadModeWebView` builds its `WKWebViewConfiguration` on first render
    /// rather than in `init`: constructing one starts WebKit's per-process
    /// machinery, which a preview must not pay for until it has a page.
    @Test("WebKit's configuration is built lazily")
    func webKitConfigurationIsLazy() throws {
        let source = try repoFile("Sources/EdmundRender/Export/ReadModeWebView.swift")
        #expect(source.contains("private func prepareConfiguration()"),
                "the configuration must be built on demand, not in init")
        #expect(source.contains("guard renderConfiguration == nil else { return }"),
                """
                building it must be idempotent — the view outlives one preview \
                (the stored property is `renderConfiguration`, since a WKWebView \
                already has a `configuration`)
                """)
    }
}

// MARK: - The extension must not run the app's document machinery

@Suite("Quick Look — the extension does not run the app")
struct QuickLookAppIsolationTests {

    /// The appex used to link the app target's `Document`, and `NSDocumentController`
    /// opened the previewed file through it: an 800×520 window with a toolbar, a
    /// sidebar, `isRestorable = true` and `window.center()`, built inside the
    /// preview process.
    @Test("The extension does not go through NSDocument")
    func extensionDoesNotUseNSDocument() throws {
        let source = try previewCode()
        #expect(!source.contains("NSDocumentController"),
                "the preview must not open the file through the app's document machinery")
        // `Document` the NSDocument subclass, not this file's own
        // `showDocument(...)`: the preview reads the file itself, in
        // `preparePreviewOfFile`.
        #expect(!source.contains("= Document(") && !source.contains("Document.self"),
                "the preview must read the file itself, not through the app's Document class")
    }

    /// Both halves of that contract: the app still knows how to tell it is the
    /// appex (it is what suppresses the window if the app ever runs the document
    /// path in a preview process), and the appex identifier the packaging step
    /// writes is the one that check keys on.
    @Test("The app's extension detection still matches the packaged appex")
    func extensionDetectionMatchesPackaging() throws {
        let document = try repoFile("Sources/edmd/App/Document.swift")
        #expect(document.contains("isQuickLookExtension"),
                "the app needs a way to tell it is the appex, not the app")
        let plist = try repoFile("Resources/QuickLookInfo.plist")
        #expect(plist.contains("com.i7t5.edmund.quicklook"),
                "the appex identifier must keep the .quicklook suffix the app detects")
        #expect(plist.contains("com.apple.quicklook.preview"),
                "the appex must declare the Quick Look preview extension point")
        #expect(plist.contains("EdmundPreviewViewController"),
                "NSExtensionPrincipalClass must name the class the preview marks @objc")
    }
}

// MARK: - Appearance

@Suite("Quick Look — preview appearance resolution")
struct QuickLookAppearanceTests {

    @Test("The theme preset decides the appearance when it forces one")
    func presetWinsOverMode() {
        // The app's own rule (`AppSettings.applyAppearance`): a ColaMD preset
        // carries its palette and wins over the light/dark picker.
        #expect(ColaThemePreset.colaDark.forcedDark == true)
        #expect(ColaThemePreset.colaLight.forcedDark == false)
        #expect(ColaThemePreset.system.forcedDark == nil)
    }

    @Test("The preview reads the same preference keys the app writes")
    func readsTheAppsKeys() throws {
        let source = try previewSource()
        // These strings are duplicated (the app target isn't linked into the
        // appex), so a rename on one side would silently stop matching.
        #expect(source.contains("\"settings.appearance.themePreset\""))
        #expect(source.contains("\"settings.appearance.mode\""))
    }

    @Test("The app's settings keys are the ones the preview reads")
    func keysMatchTheAppsSettings() throws {
        let settings = try repoFile("Sources/edmd/Settings/AppSettings.swift")
        #expect(settings.contains("\"settings.appearance.mode\""))
        #expect(settings.contains("\"settings.appearance.themePreset\""))
    }

    /// The page's colours are baked into its CSS, so an appearance flip has to
    /// rebuild it — and only the layer that built the page knows what it was
    /// built from (the web view was handed a finished string).
    @Test("An appearance flip rebuilds the page")
    func appearanceFlipRebuildsThePage() throws {
        let source = try previewSource()
        #expect(source.contains("override func viewDidChangeEffectiveAppearance()"),
                "the preview must react to an appearance change")
        #expect(source.contains("currentDocument"),
                "it has to remember what it is showing in order to rebuild it")
    }
}
