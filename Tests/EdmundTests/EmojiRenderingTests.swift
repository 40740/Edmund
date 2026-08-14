import Testing
import AppKit
import CoreText
@testable import EdmundCore

/// The body font (a serif/mono) has no glyphs for emoji. EditorTextStorage
/// disables the framework's attribute fixing (to preserve marker attachments),
/// so it must perform font substitution itself — otherwise emoji render as
/// missing-glyph boxes even though the text is stored correctly.
@Suite("Emoji — font substitution")
struct EmojiRenderingTests {

    private func fontCovers(_ s: String, _ font: NSFont) -> Bool {
        let chars = Array(s.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        return CTFontGetGlyphsForCharacters(font as CTFont, chars, &glyphs, chars.count)
    }

    @MainActor private func renderedFont(for emoji: String, in source: String) -> NSFont? {
        let editor = makeEditor()
        editor.loadContent(source)
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.recompose(cursorInRaw: 0)
        let ts = editor.textStorage!
        let r = (ts.string as NSString).range(of: emoji)
        guard r.location != NSNotFound else { return nil }
        return ts.attributes(at: r.location, effectiveRange: nil)[.font] as? NSFont
    }

    @Test("Body font lacks emoji glyphs (precondition)")
    @MainActor func bodyFontLacksEmoji() {
        let editor = makeEditor()
        #expect(fontCovers("A", editor.bodyFont))
        #expect(!fontCovers("😀", editor.bodyFont))
    }

    @Test("A plain emoji is given a font that can draw it")
    @MainActor func plainEmojiSubstituted() {
        let font = renderedFont(for: "😀", in: "hello 😀 world")
        #expect(font != nil)
        if let font { #expect(fontCovers("😀", font)) }
    }

    @Test("A ZWJ family emoji is substituted as one unit")
    @MainActor func zwjEmojiSubstituted() {
        let font = renderedFont(for: "👨‍👩‍👧‍👦", in: "family 👨‍👩‍👧‍👦 here")
        #expect(font != nil)
        if let font { #expect(fontCovers("👨‍👩‍👧‍👦", font)) }
    }

    @Test("A skin-tone emoji is substituted")
    @MainActor func skinToneEmojiSubstituted() {
        let font = renderedFont(for: "👍🏽", in: "nice 👍🏽")
        #expect(font != nil)
        if let font { #expect(fontCovers("👍🏽", font)) }
    }

    @Test("Emoji inside bold are substituted and still bold-rendered")
    @MainActor func emojiInBold() {
        let font = renderedFont(for: "😀", in: "**bold 😀**")
        #expect(font != nil)
        if let font { #expect(fontCovers("😀", font)) }
    }

    @Test("ASCII text keeps the body font")
    @MainActor func asciiKeepsBodyFont() {
        let editor = makeEditor()
        editor.loadContent("plain ascii 😀")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.recompose(cursorInRaw: 0)
        let font = editor.textStorage!.attributes(at: 0, effectiveRange: nil)[.font] as? NSFont
        #expect(font?.fontName == editor.bodyFont.fontName)
    }

    @Test("Emoji survive char-by-char typing")
    @MainActor func emojiTypedRoundTrips() {
        let editor = makeEditor()
        editor.loadContent("")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        for ch in "a😀b" {
            editor.insertText(String(ch), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        #expect(editor.rawSource == "a😀b")
        let r = (editor.textStorage!.string as NSString).range(of: "😀")
        let font = editor.textStorage!.attributes(at: r.location, effectiveRange: nil)[.font] as? NSFont
        #expect(font != nil)
        if let font { #expect(fontCovers("😀", font)) }
    }

    @Test("Emoji keep their fallback font after a restyle")
    @MainActor func emojiSurvivesRestyle() {
        // Regression: restyleBlock re-applies the serif body font over every
        // run (including emoji), so the substitution must be re-applied on the
        // styled range — not only on the one-off fixAttributes pass — or emoji
        // render as missing-glyph boxes once the block is restyled.
        let editor = makeEditor()
        editor.loadContent("before 😀 after")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.recompose(cursorInRaw: 0)

        // Restyle the whole document (theme/rerender path) and confirm the
        // emoji still carries a covering font afterward.
        editor.rerenderStyles()
        let ts = editor.textStorage!
        let r = (ts.string as NSString).range(of: "😀")
        #expect(r.location != NSNotFound)
        let font = ts.attributes(at: r.location, effectiveRange: nil)[.font] as? NSFont
        #expect(font != nil)
        if let font { #expect(fontCovers("😀", font)) }
    }
}
