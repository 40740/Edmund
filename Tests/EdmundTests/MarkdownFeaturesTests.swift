import Testing
import AppKit
@testable import EdmundCore

/// Every Markdown extension is individually toggleable. These assert both
/// directions: the syntax parses/renders with its flag set, and falls back to
/// plain text when the flag is cleared — in the editor parse layer and the
/// Read-mode HTML back-end.
@Suite("Markdown feature toggles")
struct MarkdownFeaturesTests {

    private func hasKind(_ spans: [SyntaxHighlighter.Span],
                         _ pred: (SyntaxHighlighter.Span.Kind) -> Bool) -> Bool {
        spans.contains { pred($0.kind) }
    }
    private func imageSpan(_ spans: [SyntaxHighlighter.Span]) -> (String, Int?, Int?)? {
        for s in spans { if case .image(let d, let w, let h) = s.kind { return (d, w, h) } }
        return nil
    }

    // MARK: - Parse-layer gating (both directions)

    @Test("Highlight parses only with the flag set")
    func highlight() {
        #expect(hasKind(SyntaxHighlighter.parse("==hi==", features: .all)) { $0 == .highlight })
        #expect(!hasKind(SyntaxHighlighter.parse("==hi==", features: MarkdownFeatures.all.subtracting(.highlight))) { $0 == .highlight })
    }

    @Test("Wikilink parses only with the flag set")
    func wikilink() {
        #expect(hasKind(SyntaxHighlighter.parse("[[Note]]", features: .all)) { if case .wikilink = $0 { return true }; return false })
        #expect(!hasKind(SyntaxHighlighter.parse("[[Note]]", features: MarkdownFeatures.all.subtracting(.wikilink))) { if case .wikilink = $0 { return true }; return false })
    }

    @Test("Inline comment parses only with the flag set")
    func comment() {
        #expect(hasKind(SyntaxHighlighter.parse("%%hidden%%", features: .all)) { $0 == .comment })
        #expect(!hasKind(SyntaxHighlighter.parse("%%hidden%%", features: MarkdownFeatures.all.subtracting(.inlineComment))) { $0 == .comment })
    }

    @Test("Footnote parses only with the flag set")
    func footnote() {
        #expect(hasKind(SyntaxHighlighter.parse("text[^1]", features: .all)) { if case .footnoteReference = $0 { return true }; return false })
        #expect(!hasKind(SyntaxHighlighter.parse("text[^1]", features: MarkdownFeatures.all.subtracting(.footnote))) { if case .footnoteReference = $0 { return true }; return false })
    }

    @Test("Math parses only with the flag set")
    func math() {
        #expect(hasKind(SyntaxHighlighter.parse("$x+1$", features: .all)) { if case .math = $0 { return true }; return false })
        #expect(!hasKind(SyntaxHighlighter.parse("$x+1$", features: MarkdownFeatures.all.subtracting(.math))) { if case .math = $0 { return true }; return false })
    }

    // MARK: - Image dimensions

    @Test("Image dimensions: |200 sets width, |200x100 sets both")
    func imageDimensions() {
        let w = imageSpan(SyntaxHighlighter.parse("![a|200](p.png)", features: .all))
        #expect(w?.1 == 200 && w?.2 == nil)
        let wh = imageSpan(SyntaxHighlighter.parse("![a|200x100](p.png)", features: .all))
        #expect(wh?.1 == 200 && wh?.2 == 100)
    }

    @Test("Image dimensions ignored when the flag is cleared")
    func imageDimensionsOff() {
        let off = imageSpan(SyntaxHighlighter.parse("![a|200](p.png)",
                                                    features: MarkdownFeatures.all.subtracting(.imageDimensions)))
        #expect(off?.1 == nil && off?.2 == nil)
    }

    @Test("Non-numeric |segment is a normal alt, not a size")
    func imageDimensionsNonNumeric() {
        let s = imageSpan(SyntaxHighlighter.parse("![caption|left](p.png)", features: .all))
        #expect(s?.1 == nil && s?.2 == nil)
    }

    // MARK: - Wikilink image embed

    @Test("![[file]] becomes an image span at the file, |200 sizes it")
    func wikilinkEmbed() {
        let plain = imageSpan(SyntaxHighlighter.parse("![[pic.png]]", features: .all))
        #expect(plain?.0 == "pic.png")
        let sized = imageSpan(SyntaxHighlighter.parse("![[pic.png|200]]", features: .all))
        #expect(sized?.0 == "pic.png" && sized?.1 == 200)
    }

    @Test("![[file]] stays literal (no image, no wikilink) when embeds are off")
    func wikilinkEmbedOff() {
        let spans = SyntaxHighlighter.parse("![[pic.png]]", features: MarkdownFeatures.all.subtracting(.wikilinkEmbed))
        #expect(imageSpan(spans) == nil)
        #expect(!hasKind(spans) { if case .wikilink = $0 { return true }; return false })
    }

    // MARK: - Collapsible callout marker

    @Test("Fold marker parses: - folded, + expanded, none nil")
    func foldMarker() {
        #expect(Callout.parseMarker("[!note]-")?.fold == .folded)
        #expect(Callout.parseMarker("[!note]+")?.fold == .expanded)
        #expect(Callout.parseMarker("[!note]")?.fold == nil)
        // The type is unaffected by the fold suffix.
        #expect(Callout.parseMarker("[!note]-")?.type == "note")
    }

    // MARK: - Editor render gating

    @MainActor
    @Test("Callout renders as a plain quote when callouts are off")
    func calloutRenderOff() {
        let editor = makeEditor()
        editor.markdownFeatures = MarkdownFeatures.all.subtracting(.callout)
        let styled = editor.styleBlock("> [!note]\n> body")
        // No header overlay on "[", and the raw marker isn't hidden.
        #expect(styled.attribute(.fragmentOverlay, at: 2, effectiveRange: nil) == nil)
        #expect(!isHidden(at: 3, in: styled))
    }

    @MainActor
    @Test("Callout still renders (overlay + hidden marker) when callouts are on")
    func calloutRenderOn() {
        let editor = makeEditor()   // defaults to .all
        let styled = editor.styleBlock("> [!note]\n> body")
        #expect(styled.attribute(.fragmentOverlay, at: 2, effectiveRange: nil) != nil)
        #expect(isHidden(at: 3, in: styled))
    }

    // MARK: - Read-mode HTML gating

    private func html(_ src: String, _ features: MarkdownFeatures) -> String {
        HTMLRenderer.render(markdown: src, options: ReadRenderOptions(features: features))
    }

    @Test("Read: callout div only when callouts are on")
    func readCallout() {
        #expect(html("> [!note]\n> body", .all).contains("callout"))
        #expect(!html("> [!note]\n> body", MarkdownFeatures.all.subtracting(.callout)).contains("callout"))
    }

    @Test("Read: collapsible callout emits <details>; + starts open")
    func readCollapsible() {
        let folded = html("> [!note]-\n> body", .all)
        #expect(folded.contains("<details") && folded.contains("callout-collapsible"))
        #expect(!folded.contains(" open>"))
        let expanded = html("> [!note]+\n> body", .all)
        #expect(expanded.contains("<details") && expanded.contains(" open>"))
    }

    @Test("Read: collapsible marker is a plain callout div when the flag is off")
    func readCollapsibleOff() {
        let h = html("> [!note]-\n> body", MarkdownFeatures.all.subtracting(.collapsibleCallout))
        #expect(!h.contains("<details"))
        #expect(h.contains("callout"))
    }

    @Test("Read: image dimensions become width/height attributes")
    func readImageDimensions() {
        #expect(html("![a|200](p.png)", .all).contains("width=\"200\""))
        #expect(!html("![a|200](p.png)", MarkdownFeatures.all.subtracting(.imageDimensions)).contains("width=\"200\""))
    }

    @Test("Read: ![[file]] embed emits an md-image placeholder")
    func readWikilinkEmbed() {
        #expect(html("![[pic.png]]", .all).contains("data-src=\"pic.png\""))
        #expect(!html("![[pic.png]]", MarkdownFeatures.all.subtracting(.wikilinkEmbed)).contains("data-src=\"pic.png\""))
    }

    @Test("Read: wikilink anchor only when wikilinks are on")
    func readWikilink() {
        #expect(html("[[Note]]", .all).contains("class=\"wikilink\""))
        #expect(!html("[[Note]]", MarkdownFeatures.all.subtracting(.wikilink)).contains("class=\"wikilink\""))
    }
}
