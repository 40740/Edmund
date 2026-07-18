import Testing
import AppKit
@testable import EdmundCore

/// Obsidian `#tag` and `^blockid` (Phase 2, inline pair). Style-only: a pill /
/// dim, no navigation. Each is gated by its own `MarkdownFeatures` flag.
@Suite("Tag & block-ref")
struct TagBlockRefTests {

    private func tagName(_ spans: [SyntaxHighlighter.Span]) -> String? {
        for s in spans { if case .tag(let n) = s.kind { return n } }
        return nil
    }
    private func blockRefID(_ spans: [SyntaxHighlighter.Span]) -> String? {
        for s in spans { if case .blockRef(let id) = s.kind { return id } }
        return nil
    }
    private func html(_ src: String, _ features: MarkdownFeatures) -> String {
        HTMLRenderer.render(markdown: src, options: ReadRenderOptions(features: features))
    }

    // MARK: - #tag parse

    @Test("#tag parses; the leading # is part of the token, name excludes it")
    func tagParses() {
        #expect(tagName(SyntaxHighlighter.parse("a #foo b", features: .all)) == "foo")
    }

    @Test("Nested #a/b tag keeps the slash in the name")
    func tagNested() {
        #expect(tagName(SyntaxHighlighter.parse("#a/b", features: .all)) == "a/b")
    }

    @Test("'# heading' is not a tag (space after #), and #123 is not (all digits)")
    func tagNonMatches() {
        #expect(tagName(SyntaxHighlighter.parse("# heading", features: .all)) == nil)
        #expect(tagName(SyntaxHighlighter.parse("#123", features: .all)) == nil)
    }

    @Test("A tag mid-word is not matched (must follow start or whitespace)")
    func tagRequiresBoundary() {
        #expect(tagName(SyntaxHighlighter.parse("email#foo", features: .all)) == nil)
    }

    @Test("#tag not parsed when the flag is cleared")
    func tagOff() {
        #expect(tagName(SyntaxHighlighter.parse("#foo", features: MarkdownFeatures.all.subtracting(.tag))) == nil)
    }

    // MARK: - ^blockid parse

    @Test("Trailing ^blockid parses; id excludes the caret")
    func blockRefParses() {
        #expect(blockRefID(SyntaxHighlighter.parse("some text ^abc123", features: .all)) == "abc123")
    }

    @Test("^id only matches at the end of the block, not mid-text")
    func blockRefTrailingOnly() {
        #expect(blockRefID(SyntaxHighlighter.parse("a ^abc more text", features: .all)) == nil)
    }

    @Test("^blockid not parsed when the flag is cleared")
    func blockRefOff() {
        #expect(blockRefID(SyntaxHighlighter.parse("text ^abc", features: MarkdownFeatures.all.subtracting(.blockRef))) == nil)
    }

    // MARK: - Read HTML

    @Test("Read: #tag emits a .tag span; absent when the flag is off")
    func readTag() {
        #expect(html("#foo", .all).contains("class=\"tag\""))
        #expect(html("#foo", .all).contains(">#foo<"))
        #expect(!html("#foo", MarkdownFeatures.all.subtracting(.tag)).contains("class=\"tag\""))
    }

    @Test("Read: ^blockid is hidden (never emitted)")
    func readBlockRef() {
        #expect(!html("text ^abc", .all).contains("abc"))
        // With the flag off it is not a block-ref, so the literal survives.
        #expect(html("text ^abc", MarkdownFeatures.all.subtracting(.blockRef)).contains("abc"))
    }

    // MARK: - Edit styling

    @MainActor
    @Test("Edit: #tag gets a background pill attribute")
    func editTagPill() {
        let editor = makeEditor()
        let styled = editor.styleBlock("#foo")
        #expect(styled.attribute(.backgroundColor, at: 1, effectiveRange: nil) != nil)
    }

    @MainActor
    @Test("^blockid hides in reading view, stays visible (dimmed) in edit")
    func editBlockRefHiding() {
        let editor = makeEditor()
        // "some ^abc" → the caret `^` sits at index 5.
        let reading = editor.styleBlock("some ^abc", cursorPosition: nil, hideComments: true)
        #expect(isHidden(at: 5, in: reading))
        let edit = editor.styleBlock("some ^abc", cursorPosition: nil)
        #expect(!isHidden(at: 5, in: edit))
    }
}
