import Testing
import AppKit
@testable import EdmundCore

// MARK: - Quick Look preview robustness (issue #8, second round)
//
// The first fix stopped the extension *crashing* on a Space-bar preview; the
// preview then still hung on "loading" forever. Quick Look shows its spinner
// until `preparePreviewOfFile` returns, and that method awaited the web view's
// load-finished callback with no way out and no error path — so a render that
// never finished (or never started) pinned the preview in its loading state
// with nothing anywhere saying why.
//
// These tests pin the pieces of that fix that can be checked without a
// window server: the degraded-render signal the preview reports on screen, and
// the plain-text image fallback that keeps a sandboxed preview readable.

@Suite("Quick Look preview — degraded render reporting & image fallback")
@MainActor
struct QuickLookPreviewRobustnessTests {

    /// A render that needs no fallback must not report itself as degraded —
    /// otherwise every preview would carry the "some content couldn't be
    /// rendered" notice and the signal would be worthless.
    @Test("A plain document renders exactly, and reports no degradation")
    func cleanRenderIsNotDegraded() {
        _ = DocumentHTML.full(markdown: "# Title\n\nJust prose, $x$ and `code`.",
                              theme: .quickLook, callouts: Callout.defaultStyles, dark: false)
        #expect(DocumentHTML.lastPassDegraded == false)
    }

    /// The flag must describe *this* render, not accumulate across renders in a
    /// long-lived process (Quick Look reuses one extension process for previews).
    @Test("The degraded flag is reset by each render")
    func degradedFlagResetsPerRender() {
        // A remote image is blocked by default, which is a visible fallback.
        _ = DocumentHTML.full(markdown: "![alt](https://example.com/x.png)",
                              theme: .quickLook, callouts: Callout.defaultStyles, dark: false)
        #expect(DocumentHTML.lastPassDegraded)
        _ = DocumentHTML.full(markdown: "no assets here",
                              theme: .quickLook, callouts: Callout.defaultStyles, dark: false)
        #expect(DocumentHTML.lastPassDegraded == false)
    }

    /// With the fallback on, an unshowable image leaves the author's alt text in
    /// the page instead of a placeholder icon — the difference between a preview
    /// that reads as the document and one that reads as a wall of warnings.
    @Test("Plain-text fallback keeps the alt text where the image was")
    func plainTextFallbackKeepsAltText() {
        var options = ReadRenderOptions()
        options.plainTextImageFallback = true
        let out = DocumentHTML.full(markdown: "before ![架构图](missing.png) after",
                                    theme: .quickLook, callouts: Callout.defaultStyles,
                                    dark: false, options: options)
        #expect(out.contains("md-image-omitted"))
        #expect(out.contains("架构图"))
        #expect(!out.contains("md-image-blocked"))
        #expect(DocumentHTML.lastPassDegraded, "a replaced image still counts as degraded")
    }

    /// With no alt text the source path stands in, so the reader can still tell
    /// which image the author meant.
    @Test("Plain-text fallback falls back to the source path when there is no alt")
    func plainTextFallbackUsesSourcePath() {
        var options = ReadRenderOptions()
        options.plainTextImageFallback = true
        let out = DocumentHTML.full(markdown: "![](missing.png)",
                                    theme: .quickLook, callouts: Callout.defaultStyles,
                                    dark: false, options: options)
        #expect(out.contains("missing.png"))
        #expect(!out.contains("md-image-blocked"))
    }

    /// The app's own render (and PDF/print export, which shares this assembly)
    /// keeps the icon + reason: it *can* read the file, so a placeholder means
    /// something is genuinely wrong and a reason is what the user needs.
    @Test("Without the fallback an unshowable image still gets the icon and reason")
    func defaultKeepsPlaceholderIcon() {
        let out = DocumentHTML.full(markdown: "![x](https://example.com/x.png)",
                                    theme: .default, callouts: Callout.defaultStyles, dark: false)
        #expect(out.contains("md-image-blocked"))
        #expect(out.contains("External images blocked"))
        #expect(!out.contains("md-image-omitted"))
    }

    /// The alt text reaches the page as *text*, not markup: the renderer escapes
    /// it for an attribute, and the fallback un-escapes then re-escapes for the
    /// element body, so an author's `<` can't become a tag either way.
    @Test("Alt text is escaped on the way into the page")
    func plainTextFallbackEscapesAltText() {
        var options = ReadRenderOptions()
        options.plainTextImageFallback = true
        let out = DocumentHTML.full(markdown: "![a <script>b</script>](missing.png)",
                                    theme: .quickLook, callouts: Callout.defaultStyles,
                                    dark: false, options: options)
        #expect(!out.contains("<script>"))
        #expect(out.contains("&lt;script&gt;"))
    }
}
