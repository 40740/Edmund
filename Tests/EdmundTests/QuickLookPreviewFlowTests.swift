import Testing
import Foundation
@testable import EdmundCore

// MARK: - Quick Look preview flow (issue #8, third round)
//
// The second-round fix stopped the extension crashing and bounded the wait for
// the web view's load callback — but the preview still only ever showed anything
// *if that callback arrived*. Quick Look holds its own loading state until
// `preparePreviewOfFile` returns, so an extension whose main actor was blocked
// (or whose WebKit handoff never came) still sat on the spinner.
//
// The third-round change inverts the contract: `preparePreviewOfFile` returns a
// view that is *already* a complete preview. Nothing it does waits. These tests
// pin the parts of that contract that are checkable without a window server —
// the source shapes that make "the preview always answers" true, and the
// appearance resolution the preview renders with.

@Suite("Quick Look — the preview always answers")
struct QuickLookPreviewFlowTests {

    /// The extension's own source, read from the repo, so the invariants below
    /// can be asserted where they actually live. A unit test can't launch a
    /// Quick Look appex (it needs the host, a window server and a signed bundle),
    /// so the contract is pinned at the source level — the same approach
    /// `QuickLookPackagingTests` takes for the packaging step.
    private func previewSource() throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EdmundTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sources/EdmundQuickLook/PreviewViewController.swift"),
                   encoding: .utf8)
    }

    /// The invariant the whole third-round fix rests on: `preparePreviewOfFile`
    /// must not await anything that has to *finish* before it returns. The
    /// previous revision awaited the web view's load behind an 8-second deadline;
    /// that deadline is exactly what a stuck main actor couldn't reach.
    @Test("preparePreviewOfFile awaits nothing that has to finish first")
    func prepareDoesNotWait() throws {
        let source = try previewSource()
        guard let start = source.range(of: "func preparePreviewOfFile"),
              let end = source.range(of: "// MARK: - Rendering", range: start.upperBound..<source.endIndex)
        else {
            Issue.record("could not locate preparePreviewOfFile in the preview source")
            return
        }
        let body = String(source[start.lowerBound..<end.lowerBound])
        // `await` on a continuation / sleep / Task.value is the shape of "this
        // method is waiting for something else to happen". Anything else is fine.
        for banned in ["await withCheckedContinuation", "Task.sleep", "await waitFor",
                       "withUnsafeContinuation"] {
            #expect(!body.contains(banned),
                    "preparePreviewOfFile must not wait (\(banned)) — Quick Look stays on its spinner until it returns")
        }
    }

    /// Whatever the render does, the view handed back must be a finished preview.
    /// The web view is the piece that depends on WebKit, so it may never be the
    /// view this method returns directly.
    @Test("The returned view is the container, never the web view")
    func returnsContainerNotWebView() throws {
        let source = try previewSource()
        #expect(source.contains("private final class PreviewContainer"),
                "the preview needs a plain container it can return immediately")
        // The container is what `documentView` returns, with the web view hidden
        // inside it until its own callback reveals it.
        #expect(source.contains("webView.isHidden = true"),
                "the web view must start hidden — it is revealed by its load callback")
        #expect(source.contains("container.addSubview(webView)"),
                "the web view lives inside the container that is returned")
    }

    /// The web view is frame-based inside the container (see `documentView`), so
    /// the container has to pass its own size down. An Auto Layout web view with
    /// no intrinsic size lays out to zero and renders nothing — a blank preview
    /// that no callback could ever fix.
    @Test("The web view is sized from the container, not by Auto Layout")
    func webViewIsSizedFromTheContainer() throws {
        let source = try previewSource()
        #expect(source.contains("webView.autoresizingMask = [.width, .height]"),
                "the web view must follow the container's size")
        #expect(!source.contains("webView.translatesAutoresizingMaskIntoConstraints = false"),
                "a constraint-based web view with no intrinsic size lays out 0×0")
    }

    /// A true load failure must not leave an empty pane: the reveal replaces the
    /// document with the reason. Previously a failed load was silent.
    @Test("A failed load surfaces a reason instead of an empty pane")
    func failedLoadShowsReason() throws {
        let source = try previewSource()
        #expect(source.contains("webView.lastLoadFailed"),
                "the reveal must check whether the load actually succeeded")
        #expect(source.contains("case loadFailed"),
                "a load failure needs its own user-visible explanation")
    }
}

// MARK: - The extension must not build the app's window (issue #8, third round)
//
// The appex links `EdmundCore`'s siblings in the app target only through
// `EdmundCore` — but `NSDocumentController` in the extension process still opens
// the previewed file through `Document`, which builds a real Edmund window
// (800×520, toolbar, sidebar) and centres it. In the extension that window is
// pure overhead: it can keep the extension busy on the main actor while the
// preview pane waits, and `isRestorable` even let it be archived.

@Suite("Quick Look — no app window in the extension process")
struct QuickLookWindowSuppressionTests {

    private func documentSource() throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/edmd/App/Document.swift"),
                   encoding: .utf8)
    }

    @Test("The app knows it is running inside the preview extension")
    func extensionDetection() throws {
        let source = try documentSource()
        #expect(source.contains("isQuickLookExtension"),
                "the app needs a way to tell it is the appex, not the app")
        // The bundle identifier is the signal, and it must match what the
        // packaging step writes (`Resources/QuickLookInfo.plist`).
        #expect(source.contains(".quicklook"),
                "detection must key on the extension's bundle identifier suffix")
    }

    @Test("The extension's document window is never centred or restorable")
    func windowIsNotPresented() throws {
        let source = try documentSource()
        #expect(source.contains("window.isRestorable = !Self.isQuickLookExtension"),
                "the extension's window must stay out of the restorable set")
        #expect(source.contains("if !Self.isQuickLookExtension { window.center() }"),
                "the extension's window must never be centred on screen")
    }

    @Test("The extension's bundle identifier is the one the detection expects")
    func bundleIdentifierMatchesDetection() throws {
        // `isQuickLookExtension` keys on a `.quicklook` suffix; the packaged
        // appex identifier is the other half of that contract.
        let plist = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/QuickLookInfo.plist"),
                               encoding: .utf8)
        #expect(plist.contains("com.i7t5.edmund.quicklook"),
                "the appex identifier must keep the .quicklook suffix the app detects")
    }
}

// MARK: - Preview appearance (issue #8, third round)
//
// The preview renders the page itself, so it resolves light/dark on its own
// rather than inheriting it from a window it never gets. Resolving it wrongly
// shows a dark page (or a light one) that no re-render fixes, because the appex
// has no window whose appearance could change.

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
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/EdmundQuickLook/PreviewViewController.swift"),
                               encoding: .utf8)
        // These strings are duplicated (the app target isn't linked into the
        // appex), so a rename on one side would silently stop matching.
        #expect(source.contains("\"settings.appearance.themePreset\""))
        #expect(source.contains("\"settings.appearance.mode\""))
    }

    @Test("The app's settings keys are the ones the preview reads")
    func keysMatchTheAppsSettings() throws {
        let settings = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/edmd/Settings/AppSettings.swift"),
                                  encoding: .utf8)
        #expect(settings.contains("\"settings.appearance.mode\""))
        #expect(settings.contains("\"settings.appearance.themePreset\""))
    }
}
