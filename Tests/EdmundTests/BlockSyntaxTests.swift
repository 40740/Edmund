import Testing
import AppKit
@testable import EdmundCore

/// Block-level Phase-2 syntax: YAML front matter and multi-block `%%…%%`
/// comments. Both are structural (`BlockParser`) and gated by their flag —
/// cleared, `---` / `%%` fall back to their existing classification.
@Suite("Block syntax (front matter & multi-block comment)")
struct BlockSyntaxTests {

    private func kinds(_ src: String, _ features: MarkdownFeatures) -> [BlockKind] {
        BlockParser.parse(src, features: features).map(\.kind)
    }
    private func html(_ src: String, _ features: MarkdownFeatures) -> String {
        HTMLRenderer.render(markdown: src, options: ReadRenderOptions(features: features))
    }

    // MARK: - Front matter

    @Test("Leading ---…--- is one frontMatter block; body follows")
    func frontMatterParses() {
        let ks = kinds("---\ntitle: x\ntags: [a]\n---\n\nbody", .all)
        #expect(ks.first == .frontMatter)
        // Exactly one front-matter block, and the body is still there.
        #expect(ks.filter { $0 == .frontMatter }.count == 1)
        #expect(ks.contains { if case .paragraph = $0 { return true }; return false })
    }

    @Test("With the flag cleared, leading --- is a thematic break, not front matter")
    func frontMatterOff() {
        let ks = kinds("---\ntitle: x\n---\n\nbody", MarkdownFeatures.all.subtracting(.frontMatter))
        #expect(!ks.contains(.frontMatter))
        #expect(ks.first == .thematicBreak)
    }

    @Test("A lone --- (no closing fence) stays a thematic break")
    func frontMatterNeedsClose() {
        #expect(kinds("---\n# Heading", .all).first == .thematicBreak)
        #expect(kinds("---", .all).first == .thematicBreak)
    }

    @Test("A mid-document ---…--- is not front matter")
    func frontMatterOnlyAtStart() {
        let ks = kinds("intro\n\n---\na: b\n---\n\nbody", .all)
        #expect(!ks.contains(.frontMatter))
    }

    @Test("Read: front matter is omitted when on, rendered as <hr> when off")
    func readFrontMatter() {
        let on = html("---\ntitle: x\n---\n\nbody", .all)
        #expect(!on.contains("title") && on.contains("body"))
        let off = html("---\ntitle: x\n---\n\nbody", MarkdownFeatures.all.subtracting(.frontMatter))
        #expect(off.contains("<hr"))
    }

    @MainActor
    @Test("Edit: a front-matter block is dim monospace, YAML not markdown-parsed")
    func editFrontMatter() {
        let editor = makeEditor()
        paste("---\n- notalist\n---\n\nbody", into: editor)
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.recomposeAllDirty()
        guard let ts = editor.textStorage else { Issue.record("no storage"); return }
        // The `- notalist` inside front matter must NOT become a list marker;
        // the whole fence is dim + monospace. Check the `t` of "title"/"-".
        let font = ts.attribute(.font, at: 4, effectiveRange: nil) as? NSFont
        #expect(font?.fontName.contains("Mono") == true || font!.isFixedPitch)
        let fg = ts.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor
        #expect(fg == editor.syntaxDimColor)
    }

    // MARK: - Multi-block comment

    @Test("A %%…%% spanning a blank line merges to one multiBlockComment block")
    func multiBlockMerges() {
        let ks = kinds("%%\nhidden\n\nstill hidden\n%%\n\nvisible", .all)
        #expect(ks.first == .multiBlockComment)
        #expect(ks.filter { $0 == .multiBlockComment }.count == 1)
    }

    @Test("With the flag cleared, the %% lines are not merged into a comment block")
    func multiBlockOff() {
        let ks = kinds("%%\nhidden\n\nstill\n%%", MarkdownFeatures.all.subtracting(.multiBlockComment))
        #expect(!ks.contains(.multiBlockComment))
    }

    @Test("A single-line %%x%% is left alone (inline comment, not a block)")
    func singleLineCommentUnaffected() {
        let ks = kinds("%%just inline%%", .all)
        #expect(!ks.contains(.multiBlockComment))
    }

    @Test("Read: a block-spanning %% comment body is dropped when on")
    func readMultiBlockComment() {
        let on = html("%%\nsecret note\n\nmore secret\n%%\n\nvisible", .all)
        #expect(!on.contains("secret") && on.contains("visible"))
        // Off: the comment isn't stripped, so its text survives in some form.
        let off = html("%%\nsecret note\n%%\n\nvisible", MarkdownFeatures.all.subtracting(.multiBlockComment))
        #expect(off.contains("visible"))
    }
}
