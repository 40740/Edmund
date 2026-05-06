import Testing
import AppKit
@testable import MarkdownEditorCore

// MARK: - Shared Helpers

@MainActor
private func makeEditor() -> EditorTextView {
    let textStorage = NSTextStorage()
    let layoutManager = NSLayoutManager()
    textStorage.addLayoutManager(layoutManager)
    let textContainer = NSTextContainer(
        size: NSSize(width: 500, height: CGFloat.greatestFiniteMagnitude)
    )
    textContainer.widthTracksTextView = true
    layoutManager.addTextContainer(textContainer)
    return EditorTextView(
        frame: NSRect(x: 0, y: 0, width: 500, height: 300),
        textContainer: textContainer
    )
}

@MainActor
private func type(_ text: String, into editor: EditorTextView) {
    for ch in text {
        editor.insertText(String(ch), replacementRange: NSRange(location: NSNotFound, length: 0))
    }
}

@MainActor
private func paste(_ text: String, into editor: EditorTextView) {
    editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
}

@MainActor
private func pressEnter(in editor: EditorTextView) {
    editor.insertText("\n", replacementRange: NSRange(location: NSNotFound, length: 0))
}

/// Returns the text storage string for a specific block's display range.
@MainActor
private func displayText(for blockIndex: Int, in editor: EditorTextView) -> String {
    guard blockIndex < editor.displayRanges.count else { return "" }
    let range = editor.displayRanges[blockIndex]
    let ts = editor.textStorage!
    guard range.upperBound <= ts.length else { return "" }
    return (ts.string as NSString).substring(with: range)
}

/// Returns all attributes at a given offset in the text storage.
@MainActor
private func attrs(at offset: Int, in editor: EditorTextView) -> [NSAttributedString.Key: Any] {
    let ts = editor.textStorage!
    guard offset < ts.length else { return [:] }
    return ts.attributes(at: offset, effectiveRange: nil)
}

/// Returns the font at a given offset in the text storage.
@MainActor
private func font(at offset: Int, in editor: EditorTextView) -> NSFont? {
    attrs(at: offset, in: editor)[.font] as? NSFont
}

/// Returns the foreground color at a given offset in the text storage.
@MainActor
private func fgColor(at offset: Int, in editor: EditorTextView) -> NSColor? {
    attrs(at: offset, in: editor)[.foregroundColor] as? NSColor
}

/// Switches the active block by placing the cursor at the start of a block
/// and recomposing.
@MainActor
private func activateBlock(_ index: Int, in editor: EditorTextView) {
    guard index < editor.blocks.count else { return }
    let rawOffset = editor.blocks[index].range.location
    editor.recompose(cursorInRaw: rawOffset)
}

// ============================================================================
// MARK: - Inline Styling: Active Block
// ============================================================================

@Suite("Integration — Inline Styling (Active Block)")
struct InlineStylingActiveTests {

    // MARK: - Bold

    @Test("Active **bold** has bold font on content and dimmed delimiters")
    @MainActor func activeBoldAsterisks() {
        let editor = makeEditor()
        editor.loadContent("**hello**")
        activateBlock(0, in: editor)

        // "**hello**" — delimiters at 0..1 and 7..8, content at 2..6
        let contentFont = font(at: 2, in: editor)!
        #expect(NSFontManager.shared.traits(of: contentFont).contains(.boldFontMask))

        // Delimiters should be dimmed
        let delimColor = fgColor(at: 0, in: editor)
        #expect(delimColor == NSColor.tertiaryLabelColor)
        let endDelimColor = fgColor(at: 7, in: editor)
        #expect(endDelimColor == NSColor.tertiaryLabelColor)
    }

    @Test("Active __bold__ with underscores has bold font")
    @MainActor func activeBoldUnderscores() {
        let editor = makeEditor()
        editor.loadContent("__hello__")
        activateBlock(0, in: editor)

        let contentFont = font(at: 2, in: editor)!
        #expect(NSFontManager.shared.traits(of: contentFont).contains(.boldFontMask))
    }

    // MARK: - Italic

    @Test("Active *italic* has italic font on content and dimmed delimiters")
    @MainActor func activeItalicAsterisks() {
        let editor = makeEditor()
        editor.loadContent("*hello*")
        activateBlock(0, in: editor)

        let contentFont = font(at: 1, in: editor)!
        #expect(NSFontManager.shared.traits(of: contentFont).contains(.italicFontMask))

        let delimColor = fgColor(at: 0, in: editor)
        #expect(delimColor == NSColor.tertiaryLabelColor)
    }

    @Test("Active _italic_ with underscores has italic font")
    @MainActor func activeItalicUnderscores() {
        let editor = makeEditor()
        editor.loadContent("_hello_")
        activateBlock(0, in: editor)

        let contentFont = font(at: 1, in: editor)!
        #expect(NSFontManager.shared.traits(of: contentFont).contains(.italicFontMask))
    }

    // MARK: - Bold Italic

    @Test("Active ***bolditalic*** has bold+italic font")
    @MainActor func activeBoldItalic() {
        let editor = makeEditor()
        editor.loadContent("***hello***")
        activateBlock(0, in: editor)

        let contentFont = font(at: 3, in: editor)!
        let traits = NSFontManager.shared.traits(of: contentFont)
        #expect(traits.contains(.boldFontMask))
        #expect(traits.contains(.italicFontMask))
    }

    @Test("Active ___bolditalic___ with underscores has bold+italic font")
    @MainActor func activeBoldItalicUnderscores() {
        let editor = makeEditor()
        editor.loadContent("___hello___")
        activateBlock(0, in: editor)

        let contentFont = font(at: 3, in: editor)!
        let traits = NSFontManager.shared.traits(of: contentFont)
        #expect(traits.contains(.boldFontMask))
        #expect(traits.contains(.italicFontMask))
    }

    // MARK: - Code

    @Test("Active `code` has code color on content and dimmed backticks")
    @MainActor func activeCode() {
        let editor = makeEditor()
        editor.loadContent("`code`")
        activateBlock(0, in: editor)

        let contentColor = fgColor(at: 1, in: editor)
        #expect(contentColor == editor.codeColor)

        let delimColor = fgColor(at: 0, in: editor)
        #expect(delimColor == NSColor.tertiaryLabelColor)
    }

    // MARK: - Strikethrough

    @Test("Active ~~strikethrough~~ has strikethrough attribute")
    @MainActor func activeStrikethrough() {
        let editor = makeEditor()
        editor.loadContent("~~struck~~")
        activateBlock(0, in: editor)

        let a = attrs(at: 2, in: editor)
        let style = a[.strikethroughStyle] as? Int
        #expect(style == NSUnderlineStyle.single.rawValue)
    }

    // MARK: - Highlight

    @Test("Active ==highlight== has yellow background")
    @MainActor func activeHighlight() {
        let editor = makeEditor()
        editor.loadContent("==marked==")
        activateBlock(0, in: editor)

        let a = attrs(at: 2, in: editor)
        let bg = a[.backgroundColor] as? NSColor
        #expect(bg != nil)
    }

    // MARK: - Link

    @Test("Active [link](url) has accent color on link text")
    @MainActor func activeLink() {
        let editor = makeEditor()
        editor.loadContent("[click](https://example.com)")
        activateBlock(0, in: editor)

        // "[click](url)" — "[" at 0, "click" at 1..5
        let linkColor = fgColor(at: 1, in: editor)
        #expect(linkColor == editor.accentColor)

        // Delimiter "[" should be dimmed
        let delimColor = fgColor(at: 0, in: editor)
        #expect(delimColor == NSColor.tertiaryLabelColor)
    }

    // MARK: - Combinations

    @Test("Active **bold** and *italic* on same line both styled")
    @MainActor func activeBoldAndItalic() {
        let editor = makeEditor()
        // "**bold** and *italic*"
        //  01234567890123456789012
        //  **bold**     *italic*
        editor.loadContent("**bold** and *italic*")
        activateBlock(0, in: editor)

        // Bold content at offset 2 ("bold")
        let boldFont = font(at: 2, in: editor)!
        #expect(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))

        // Italic content at offset 14 ("italic" — after "**bold** and *")
        let italicFont = font(at: 14, in: editor)!
        #expect(NSFontManager.shared.traits(of: italicFont).contains(.italicFontMask))
    }

    @Test("Active bold + code + strikethrough on same line all styled")
    @MainActor func activeMixedInline() {
        let editor = makeEditor()
        editor.loadContent("**bold** `code` ~~struck~~")
        activateBlock(0, in: editor)

        // Bold at 2
        let boldFont = font(at: 2, in: editor)!
        #expect(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))

        // Code at 10
        let codeCol = fgColor(at: 10, in: editor)
        #expect(codeCol == editor.codeColor)

        // Strikethrough at 18
        let a = attrs(at: 18, in: editor)
        #expect(a[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)
    }

    // MARK: - Uneven Delimiters

    @Test("Active *hi** renders as italic hi (extra * literal)")
    @MainActor func activeUnevenSingleExtra() {
        let editor = makeEditor()
        editor.loadContent("*hi**")
        activateBlock(0, in: editor)

        // swift-markdown treats this as *hi* + literal *
        // Content "hi" at offset 1
        let f = font(at: 1, in: editor)!
        #expect(NSFontManager.shared.traits(of: f).contains(.italicFontMask))
    }

    @Test("Active **hi* renders as italic (matched * pair, extra * literal)")
    @MainActor func activeUnevenDoubleOpen() {
        let editor = makeEditor()
        editor.loadContent("**hi*")
        activateBlock(0, in: editor)

        // swift-markdown: "**hi*" → *(*hi)* with inner * literal
        // The matched pair is single *, content includes the extra *
        let display = editor.textStorage!.string
        #expect(display == "**hi*")
    }
}

// ============================================================================
// MARK: - Inline Styling: Inactive Block
// ============================================================================

@Suite("Integration — Inline Styling (Inactive Block)")
struct InlineStylingInactiveTests {

    @Test("Inactive **bold** strips delimiters and applies bold font")
    @MainActor func inactiveBold() {
        let editor = makeEditor()
        editor.loadContent("**bold**\nother")
        activateBlock(1, in: editor)  // Make block 0 inactive

        let text = displayText(for: 0, in: editor)
        #expect(text == "bold")
        let f = font(at: editor.displayRanges[0].location, in: editor)!
        #expect(NSFontManager.shared.traits(of: f).contains(.boldFontMask))
    }

    @Test("Inactive __bold__ with underscores strips and applies bold")
    @MainActor func inactiveBoldUnderscores() {
        let editor = makeEditor()
        editor.loadContent("__bold__\nother")
        activateBlock(1, in: editor)

        let text = displayText(for: 0, in: editor)
        #expect(text == "bold")
        let f = font(at: editor.displayRanges[0].location, in: editor)!
        #expect(NSFontManager.shared.traits(of: f).contains(.boldFontMask))
    }

    @Test("Inactive *italic* strips delimiters and applies italic font")
    @MainActor func inactiveItalic() {
        let editor = makeEditor()
        editor.loadContent("*italic*\nother")
        activateBlock(1, in: editor)

        let text = displayText(for: 0, in: editor)
        #expect(text == "italic")
        let f = font(at: editor.displayRanges[0].location, in: editor)!
        #expect(NSFontManager.shared.traits(of: f).contains(.italicFontMask))
    }

    @Test("Inactive _italic_ with underscores strips and applies italic")
    @MainActor func inactiveItalicUnderscores() {
        let editor = makeEditor()
        editor.loadContent("_italic_\nother")
        activateBlock(1, in: editor)

        let text = displayText(for: 0, in: editor)
        #expect(text == "italic")
        let f = font(at: editor.displayRanges[0].location, in: editor)!
        #expect(NSFontManager.shared.traits(of: f).contains(.italicFontMask))
    }

    @Test("Inactive ***bolditalic*** strips delimiters and applies both traits")
    @MainActor func inactiveBoldItalic() {
        let editor = makeEditor()
        editor.loadContent("***both***\nother")
        activateBlock(1, in: editor)

        let text = displayText(for: 0, in: editor)
        #expect(text == "both")
        let f = font(at: editor.displayRanges[0].location, in: editor)!
        let traits = NSFontManager.shared.traits(of: f)
        #expect(traits.contains(.boldFontMask))
        #expect(traits.contains(.italicFontMask))
    }

    @Test("Inactive `code` strips backticks and applies code color")
    @MainActor func inactiveCode() {
        let editor = makeEditor()
        editor.loadContent("`code`\nother")
        activateBlock(1, in: editor)

        let text = displayText(for: 0, in: editor)
        #expect(text == "code")
        let color = fgColor(at: editor.displayRanges[0].location, in: editor)
        #expect(color == editor.codeColor)
    }

    @Test("Inactive ~~strikethrough~~ strips delimiters and applies strikethrough")
    @MainActor func inactiveStrikethrough() {
        let editor = makeEditor()
        editor.loadContent("~~struck~~\nother")
        activateBlock(1, in: editor)

        let text = displayText(for: 0, in: editor)
        #expect(text == "struck")
        let a = attrs(at: editor.displayRanges[0].location, in: editor)
        #expect(a[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)
    }

    @Test("Inactive ==highlight== strips delimiters and applies background color")
    @MainActor func inactiveHighlight() {
        let editor = makeEditor()
        editor.loadContent("==marked==\nother")
        activateBlock(1, in: editor)

        let text = displayText(for: 0, in: editor)
        #expect(text == "marked")
        let a = attrs(at: editor.displayRanges[0].location, in: editor)
        #expect(a[.backgroundColor] != nil)
    }

    @Test("Inactive [link](url) strips syntax, shows text with underline and accent color")
    @MainActor func inactiveLink() {
        let editor = makeEditor()
        editor.loadContent("[click](https://example.com)\nother")
        activateBlock(1, in: editor)

        let text = displayText(for: 0, in: editor)
        #expect(text == "click")
        let offset = editor.displayRanges[0].location
        let color = fgColor(at: offset, in: editor)
        #expect(color == editor.accentColor)
        let a = attrs(at: offset, in: editor)
        #expect(a[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
    }

    @Test("Inactive mixed bold + italic + code all rendered correctly")
    @MainActor func inactiveMixed() {
        let editor = makeEditor()
        editor.loadContent("**bold** *italic* `code`\nother")
        activateBlock(1, in: editor)

        let text = displayText(for: 0, in: editor)
        // Delimiters stripped: "bold italic code"
        #expect(text == "bold italic code")

        let base = editor.displayRanges[0].location
        // "bold" starts at base+0
        let bf = font(at: base, in: editor)!
        #expect(NSFontManager.shared.traits(of: bf).contains(.boldFontMask))

        // "italic" starts at base+5
        let itf = font(at: base + 5, in: editor)!
        #expect(NSFontManager.shared.traits(of: itf).contains(.italicFontMask))

        // "code" starts at base+12
        let cc = fgColor(at: base + 12, in: editor)
        #expect(cc == editor.codeColor)
    }

    @Test("Inactive *hi** renders correctly (uneven delimiters)")
    @MainActor func inactiveUnevenDelimiters() {
        let editor = makeEditor()
        editor.loadContent("*hi**\nother")
        activateBlock(1, in: editor)

        // swift-markdown: "*hi*" matches italic, trailing "*" is literal
        let text = displayText(for: 0, in: editor)
        #expect(text == "hi*")
    }
}

// ============================================================================
// MARK: - Block Styling: Active Block
// ============================================================================

@Suite("Integration — Block Styling (Active Block)")
struct BlockStylingActiveTests {

    // MARK: - Headings

    @Test("Active # heading has bold font scaled 1.5x")
    @MainActor func activeH1() {
        let editor = makeEditor()
        editor.loadContent("# Title")
        activateBlock(0, in: editor)

        let f = font(at: 2, in: editor)!
        let expectedSize = editor.bodyFont.pointSize * 1.5
        #expect(abs(f.pointSize - expectedSize) < 0.1)
        #expect(NSFontManager.shared.traits(of: f).contains(.boldFontMask))
    }

    @Test("Active ## heading has bold font scaled 1.3x")
    @MainActor func activeH2() {
        let editor = makeEditor()
        editor.loadContent("## Subtitle")
        activateBlock(0, in: editor)

        let f = font(at: 3, in: editor)!
        let expectedSize = editor.bodyFont.pointSize * 1.3
        #expect(abs(f.pointSize - expectedSize) < 0.1)
    }

    @Test("Active ### heading has bold font scaled 1.15x")
    @MainActor func activeH3() {
        let editor = makeEditor()
        editor.loadContent("### Section")
        activateBlock(0, in: editor)

        let f = font(at: 4, in: editor)!
        let expectedSize = editor.bodyFont.pointSize * 1.15
        #expect(abs(f.pointSize - expectedSize) < 0.1)
    }

    @Test("Active heading # prefix is dimmed")
    @MainActor func activeHeadingDimmedPrefix() {
        let editor = makeEditor()
        editor.loadContent("# Title")
        activateBlock(0, in: editor)

        let delimColor = fgColor(at: 0, in: editor)
        #expect(delimColor == NSColor.tertiaryLabelColor)
    }

    // MARK: - Bullet Lists

    @Test("Active - item has list paragraph style")
    @MainActor func activeBulletList() {
        let editor = makeEditor()
        editor.loadContent("- item")
        activateBlock(0, in: editor)

        let a = attrs(at: 0, in: editor)
        let ps = a[.paragraphStyle] as? NSParagraphStyle
        #expect(ps != nil)
        #expect(ps!.firstLineHeadIndent == editor.listIndent)
    }

    @Test("Active - prefix is dimmed")
    @MainActor func activeBulletDimmed() {
        let editor = makeEditor()
        editor.loadContent("- item")
        activateBlock(0, in: editor)

        let delimColor = fgColor(at: 0, in: editor)
        #expect(delimColor == NSColor.tertiaryLabelColor)
    }

    // MARK: - Numbered Lists

    @Test("Active 1. item has list paragraph style")
    @MainActor func activeNumberedList() {
        let editor = makeEditor()
        editor.loadContent("1. item")
        activateBlock(0, in: editor)

        let a = attrs(at: 0, in: editor)
        let ps = a[.paragraphStyle] as? NSParagraphStyle
        #expect(ps != nil)
        #expect(ps!.firstLineHeadIndent == editor.listIndent)
    }

    // MARK: - Todo Lists

    @Test("Active - [ ] unchecked has list paragraph style")
    @MainActor func activeTodoUnchecked() {
        let editor = makeEditor()
        editor.loadContent("- [ ] todo")
        activateBlock(0, in: editor)

        let a = attrs(at: 0, in: editor)
        let ps = a[.paragraphStyle] as? NSParagraphStyle
        #expect(ps != nil)
        #expect(ps!.firstLineHeadIndent == editor.listIndent)
    }

    // MARK: - Blockquotes

    @Test("Active > quote has dimmed > prefix")
    @MainActor func activeBlockquote() {
        let editor = makeEditor()
        editor.loadContent("> quote")
        activateBlock(0, in: editor)

        let delimColor = fgColor(at: 0, in: editor)
        #expect(delimColor == NSColor.tertiaryLabelColor)
    }
}

// ============================================================================
// MARK: - Block Styling: Inactive Block
// ============================================================================

@Suite("Integration — Block Styling (Inactive Block)")
struct BlockStylingInactiveTests {

    // MARK: - Headings

    @Test("Inactive # heading strips prefix, applies bold scaled font")
    @MainActor func inactiveH1() {
        let editor = makeEditor()
        editor.loadContent("# Title\nother")
        activateBlock(1, in: editor)

        let text = displayText(for: 0, in: editor)
        #expect(text == "Title")
        let f = font(at: editor.displayRanges[0].location, in: editor)!
        let expectedSize = editor.bodyFont.pointSize * 1.5
        #expect(abs(f.pointSize - expectedSize) < 0.1)
        #expect(NSFontManager.shared.traits(of: f).contains(.boldFontMask))
    }

    @Test("Inactive ## heading strips prefix, applies correct scale")
    @MainActor func inactiveH2() {
        let editor = makeEditor()
        editor.loadContent("## Sub\nother")
        activateBlock(1, in: editor)

        let text = displayText(for: 0, in: editor)
        #expect(text == "Sub")
        let f = font(at: editor.displayRanges[0].location, in: editor)!
        let expectedSize = editor.bodyFont.pointSize * 1.3
        #expect(abs(f.pointSize - expectedSize) < 0.1)
    }

    @Test("Inactive ### heading strips prefix, applies correct scale")
    @MainActor func inactiveH3() {
        let editor = makeEditor()
        editor.loadContent("### Sec\nother")
        activateBlock(1, in: editor)

        let text = displayText(for: 0, in: editor)
        #expect(text == "Sec")
        let f = font(at: editor.displayRanges[0].location, in: editor)!
        let expectedSize = editor.bodyFont.pointSize * 1.15
        #expect(abs(f.pointSize - expectedSize) < 0.1)
    }

    // MARK: - Bullet Lists

    @Test("Inactive - item shows bullet character and has list paragraph style")
    @MainActor func inactiveBulletList() {
        let editor = makeEditor()
        editor.loadContent("- apples\nother")
        activateBlock(1, in: editor)

        let text = displayText(for: 0, in: editor)
        #expect(text.contains("\u{2022}"))  // bullet •
        #expect(text.contains("apples"))

        let base = editor.displayRanges[0].location
        let a = attrs(at: base, in: editor)
        let ps = a[.paragraphStyle] as? NSParagraphStyle
        #expect(ps != nil)
        #expect(ps!.firstLineHeadIndent == editor.listIndent)
    }

    @Test("Inactive bullet is dimmed")
    @MainActor func inactiveBulletDimmed() {
        let editor = makeEditor()
        editor.loadContent("- apples\nother")
        activateBlock(1, in: editor)

        let base = editor.displayRanges[0].location
        let bulletColor = fgColor(at: base, in: editor)
        #expect(bulletColor == NSColor.tertiaryLabelColor)
    }

    // MARK: - Numbered Lists

    @Test("Inactive 1. item keeps number and has list paragraph style")
    @MainActor func inactiveNumberedList() {
        let editor = makeEditor()
        editor.loadContent("1. first\nother")
        activateBlock(1, in: editor)

        let text = displayText(for: 0, in: editor)
        #expect(text.contains("1."))
        #expect(text.contains("first"))

        let base = editor.displayRanges[0].location
        let a = attrs(at: base, in: editor)
        let ps = a[.paragraphStyle] as? NSParagraphStyle
        #expect(ps != nil)
    }

    @Test("Inactive ordered list number is dimmed")
    @MainActor func inactiveNumberDimmed() {
        let editor = makeEditor()
        editor.loadContent("1. first\nother")
        activateBlock(1, in: editor)

        let base = editor.displayRanges[0].location
        let numColor = fgColor(at: base, in: editor)
        #expect(numColor == NSColor.tertiaryLabelColor)
    }

    // MARK: - Todo Lists

    @Test("Inactive - [ ] unchecked shows open circle")
    @MainActor func inactiveTodoUnchecked() {
        let editor = makeEditor()
        editor.loadContent("- [ ] task\nother")
        activateBlock(1, in: editor)

        let text = displayText(for: 0, in: editor)
        #expect(text.contains("\u{25CB}"))  // ○
        #expect(text.contains("task"))
    }

    @Test("Inactive - [x] checked shows filled circle and strikethrough")
    @MainActor func inactiveTodoChecked() {
        let editor = makeEditor()
        editor.loadContent("- [x] done\nother")
        activateBlock(1, in: editor)

        let text = displayText(for: 0, in: editor)
        #expect(text.contains("\u{25CF}"))  // ●
        #expect(text.contains("done"))

        // "done" should have strikethrough
        let base = editor.displayRanges[0].location
        // Find "done" offset: "● done" → bullet(1) + space(1) + "done" at offset 2
        let doneOffset = base + 2
        let a = attrs(at: doneOffset, in: editor)
        #expect(a[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)
    }

    // MARK: - Blockquotes

    @Test("Inactive > quote strips prefix, applies secondary label color")
    @MainActor func inactiveBlockquote() {
        let editor = makeEditor()
        editor.loadContent("> wise words\nother")
        activateBlock(1, in: editor)

        let text = displayText(for: 0, in: editor)
        #expect(text == "wise words")
        let color = fgColor(at: editor.displayRanges[0].location, in: editor)
        #expect(color == NSColor.secondaryLabelColor)
    }

    @Test("Inactive > quote has blockquote paragraph style with text block")
    @MainActor func inactiveBlockquoteParagraphStyle() {
        let editor = makeEditor()
        editor.loadContent("> wise words\nother")
        activateBlock(1, in: editor)

        let a = attrs(at: editor.displayRanges[0].location, in: editor)
        let ps = a[.paragraphStyle] as? NSParagraphStyle
        #expect(ps != nil)
        #expect(!ps!.textBlocks.isEmpty)
    }

    // MARK: - Nested Content

    @Test("Inactive bold inside blockquote is rendered")
    @MainActor func inactiveBoldInBlockquote() {
        let editor = makeEditor()
        editor.loadContent("> **important**\nother")
        activateBlock(1, in: editor)

        let text = displayText(for: 0, in: editor)
        // Blockquote ">" stripped, bold "**" stripped
        #expect(text == "important")
        let f = font(at: editor.displayRanges[0].location, in: editor)!
        #expect(NSFontManager.shared.traits(of: f).contains(.boldFontMask))
    }
}

// ============================================================================
// MARK: - Block Transition (Active ↔ Inactive)
// ============================================================================

@Suite("Integration — Block Transition")
struct BlockTransitionTests {

    @Test("Switching from active to inactive renders markdown")
    @MainActor func activeToInactive() {
        let editor = makeEditor()
        editor.loadContent("**bold**\nplain")

        // Block 0 is active (cursor at 0), shows raw markdown
        activateBlock(0, in: editor)
        let activeText = displayText(for: 0, in: editor)
        #expect(activeText == "**bold**")

        // Switch to block 1 — block 0 becomes inactive, rendered
        activateBlock(1, in: editor)
        let inactiveText = displayText(for: 0, in: editor)
        #expect(inactiveText == "bold")
    }

    @Test("Switching from inactive to active shows raw markdown")
    @MainActor func inactiveToActive() {
        let editor = makeEditor()
        editor.loadContent("# Title\ntext")

        // Activate block 1 so block 0 is inactive
        activateBlock(1, in: editor)
        let inactiveText = displayText(for: 0, in: editor)
        #expect(inactiveText == "Title")

        // Activate block 0 — shows raw
        activateBlock(0, in: editor)
        let activeText = displayText(for: 0, in: editor)
        #expect(activeText == "# Title")
    }

    @Test("Multiple blocks: only active block shows raw, others rendered")
    @MainActor func multipleBlocksRendering() {
        let editor = makeEditor()
        editor.loadContent("**a**\n*b*\n`c`")

        activateBlock(1, in: editor)

        // Block 0 inactive: "a" (bold rendered)
        #expect(displayText(for: 0, in: editor) == "a")
        // Block 1 active: "*b*" (raw markdown)
        #expect(displayText(for: 1, in: editor) == "*b*")
        // Block 2 inactive: "c" (code rendered)
        #expect(displayText(for: 2, in: editor) == "c")
    }
}

// ============================================================================
// MARK: - Features: Undo/Redo
// ============================================================================

@Suite("Integration — Undo/Redo")
struct UndoRedoIntegrationTests {

    @Test("Undo typing then redo restores text and rawSource")
    @MainActor func undoRedoTyping() {
        let editor = makeEditor()
        type("hello", into: editor)
        #expect(editor.rawSource == "hello")

        editor.undo(nil)
        #expect(editor.rawSource == "")

        editor.redo(nil)
        #expect(editor.rawSource == "hello")
    }

    @Test("Undo across blocks: type, Enter, type, undo all")
    @MainActor func undoAcrossBlocks() {
        let editor = makeEditor()
        type("line1", into: editor)
        pressEnter(in: editor)
        type("line2", into: editor)
        #expect(editor.blocks.count == 2)

        editor.undo(nil)  // undo "line2"
        #expect(editor.rawSource == "line1\n")
        editor.undo(nil)  // undo Enter
        #expect(editor.rawSource == "line1")
        editor.undo(nil)  // undo "line1"
        #expect(editor.rawSource == "")
    }

    @Test("Undo paste reverts entire paste in one step")
    @MainActor func undoPaste() {
        let editor = makeEditor()
        paste("pasted text", into: editor)
        #expect(editor.rawSource == "pasted text")

        editor.undo(nil)
        #expect(editor.rawSource == "")
    }

    @Test("New edit after undo clears redo stack")
    @MainActor func editClearsRedo() {
        let editor = makeEditor()
        type("a", into: editor)
        editor.undo(nil)
        type("b", into: editor)
        editor.redo(nil)  // should do nothing
        #expect(editor.rawSource == "b")
    }

    @Test("Undo/redo with markdown content preserves rawSource exactly")
    @MainActor func undoRedoMarkdown() {
        let editor = makeEditor()
        paste("**bold** and *italic*", into: editor)
        let original = editor.rawSource

        editor.undo(nil)
        #expect(editor.rawSource == "")

        editor.redo(nil)
        #expect(editor.rawSource == original)
    }
}

// ============================================================================
// MARK: - Features: Tab to Indent
// ============================================================================

@Suite("Integration — Tab Indent")
struct TabIndentIntegrationTests {

    @Test("Type list, Tab indents, display reflects indent")
    @MainActor func typeAndIndent() {
        let editor = makeEditor()
        type("- item", into: editor)
        editor.insertTab(nil)

        #expect(editor.rawSource == "    - item")
        #expect(editor.textStorage!.string.contains("    - item"))
    }

    @Test("Tab on multi-line list indents all lines")
    @MainActor func multiLineIndent() {
        let editor = makeEditor()
        editor.loadContent("- a\n- b\n- c")

        let len = editor.textStorage!.length
        editor.setSelectedRange(NSRange(location: 0, length: len))
        editor.insertTab(nil)

        #expect(editor.blocks.count == 3)
        for block in editor.blocks {
            #expect(block.content.hasPrefix("    "))
        }
    }

    @Test("Shift-Tab dedents, Undo reverts, Redo re-applies")
    @MainActor func dedentUndoRedo() {
        let editor = makeEditor()
        editor.loadContent("    - item")
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        editor.insertBacktab(nil)
        #expect(editor.rawSource == "- item")

        editor.undo(nil)
        #expect(editor.rawSource == "    - item")

        editor.redo(nil)
        #expect(editor.rawSource == "- item")
    }

    @Test("Tab on non-list line inserts tab character, not indent")
    @MainActor func tabOnPlainText() {
        let editor = makeEditor()
        editor.loadContent("plain text")
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        editor.insertTab(nil)

        #expect(editor.rawSource.contains("\t"))
    }

    @Test("Tab on mixed ordered/unordered list indents all")
    @MainActor func tabMixedList() {
        let editor = makeEditor()
        editor.loadContent("- bullet\n1. numbered")
        let len = editor.textStorage!.length
        editor.setSelectedRange(NSRange(location: 0, length: len))
        editor.insertTab(nil)

        #expect(editor.rawSource == "    - bullet\n    1. numbered")
    }

    @Test("Multiple indent/dedent cycles are stable")
    @MainActor func multipleIndentCycles() {
        let editor = makeEditor()
        editor.loadContent("- item")
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        // Indent twice
        editor.insertTab(nil)
        editor.insertTab(nil)
        #expect(editor.rawSource == "        - item")

        // Dedent twice
        editor.insertBacktab(nil)
        editor.insertBacktab(nil)
        #expect(editor.rawSource == "- item")
    }
}

// ============================================================================
// MARK: - Appearance: Font
// ============================================================================

@Suite("Integration — Font")
struct FontIntegrationTests {

    @Test("Default font is used in base attributes")
    @MainActor func defaultFont() {
        let editor = makeEditor()
        editor.loadContent("hello")
        activateBlock(0, in: editor)

        let f = font(at: 0, in: editor)
        #expect(f == editor.bodyFont)
    }

    @Test("updateFont changes body font and recomposes")
    @MainActor func updateFontChanges() {
        let editor = makeEditor()
        editor.loadContent("hello")

        // Set to a known font first so we have a stable baseline
        editor.updateFont(name: "Menlo", size: 12)
        #expect(editor.bodyFont.familyName == "Menlo")

        // Now change to a different font
        editor.updateFont(name: "Helvetica", size: 20)
        #expect(editor.bodyFont.familyName == "Helvetica")
        #expect(editor.bodyFont.pointSize == 20)

        // Verify text storage uses the new font
        let f = font(at: 0, in: editor)
        #expect(f?.familyName == "Helvetica")
        #expect(f?.pointSize == 20)
    }

    @Test("updateFont affects bold rendering")
    @MainActor func updateFontAffectsBold() {
        let editor = makeEditor()
        editor.loadContent("**bold**")
        editor.updateFont(name: "Helvetica", size: 24)
        activateBlock(0, in: editor)

        let f = font(at: 2, in: editor)!
        #expect(NSFontManager.shared.traits(of: f).contains(.boldFontMask))
        #expect(f.pointSize == 24)
    }

    @Test("updateFont affects heading scale")
    @MainActor func updateFontAffectsHeading() {
        let editor = makeEditor()
        editor.loadContent("# Title")
        editor.updateFont(name: "Helvetica", size: 20)
        activateBlock(0, in: editor)

        let f = font(at: 2, in: editor)!
        let expectedSize = 20.0 * 1.5
        #expect(abs(f.pointSize - expectedSize) < 0.1)
    }

    @Test("updateFont affects inactive block rendering")
    @MainActor func updateFontInactive() {
        let editor = makeEditor()
        editor.loadContent("**bold**\nother")
        editor.updateFont(name: "Helvetica", size: 18)
        activateBlock(1, in: editor)

        let f = font(at: editor.displayRanges[0].location, in: editor)!
        #expect(NSFontManager.shared.traits(of: f).contains(.boldFontMask))
        #expect(f.pointSize == 18)
    }

    @Test("Font size change persists to UserDefaults")
    @MainActor func fontPersistence() {
        let editor = makeEditor()
        editor.updateFont(name: "Courier", size: 14)

        let savedName = UserDefaults.standard.string(forKey: "EditorFontName")
        let savedSize = UserDefaults.standard.float(forKey: "EditorFontSize")
        #expect(savedName == "Courier")
        #expect(savedSize == 14)
    }

    @Test("Invalid font name falls back to system font")
    @MainActor func invalidFontFallback() {
        let editor = makeEditor()
        editor.updateFont(name: "NonExistentFont12345", size: 16)

        #expect(editor.bodyFont.pointSize == 16)
        // Should be a system font since the name is invalid
        #expect(editor.bodyFont == NSFont.systemFont(ofSize: 16))
    }
}

// ============================================================================
// MARK: - Appearance: Colors & Dark Mode
// ============================================================================

@Suite("Integration — Appearance")
struct AppearanceIntegrationTests {

    @Test("Editor background uses textBackgroundColor")
    @MainActor func editorBackground() {
        let editor = makeEditor()
        #expect(editor.backgroundColor == NSColor.textBackgroundColor)
    }

    @Test("Insertion point uses textColor")
    @MainActor func insertionPoint() {
        let editor = makeEditor()
        #expect(editor.insertionPointColor == NSColor.textColor)
    }

    @Test("Body text uses textColor")
    @MainActor func bodyTextColor() {
        let editor = makeEditor()
        editor.loadContent("hello")
        activateBlock(0, in: editor)

        let color = fgColor(at: 0, in: editor)
        #expect(color == NSColor.textColor)
    }

    @Test("Selection attributes use accent color with alpha")
    @MainActor func selectionAttributes() {
        let editor = makeEditor()
        let selAttrs = editor.selectedTextAttributes
        let bg = selAttrs[.backgroundColor] as? NSColor
        #expect(bg != nil)
    }

    @Test("viewDidChangeEffectiveAppearance recomposes")
    @MainActor func appearanceChange() {
        let editor = makeEditor()
        editor.loadContent("**bold**")
        activateBlock(0, in: editor)

        // Trigger appearance change callback
        editor.viewDidChangeEffectiveAppearance()

        // Editor should still have correct content after recompose
        #expect(editor.rawSource == "**bold**")
        let display = editor.textStorage!.string
        #expect(display == "**bold**")
    }

    @Test("Accent color is used for link text in active block")
    @MainActor func accentColorActiveLink() {
        let editor = makeEditor()
        editor.loadContent("[link](url)")
        activateBlock(0, in: editor)

        let color = fgColor(at: 1, in: editor)
        #expect(color == editor.accentColor)
    }

    @Test("Code color is used for inline code in both active and inactive")
    @MainActor func codeColorBothStates() {
        let editor = makeEditor()
        editor.loadContent("`active`\n`inactive`")

        // Active block 0
        activateBlock(0, in: editor)
        let activeColor = fgColor(at: 1, in: editor)
        #expect(activeColor == editor.codeColor)

        // Switch to block 1, making block 0 inactive
        activateBlock(1, in: editor)
        let inactiveColor = fgColor(at: editor.displayRanges[0].location, in: editor)
        #expect(inactiveColor == editor.codeColor)
    }

    @Test("Syntax delimiter dimming uses tertiaryLabelColor")
    @MainActor func delimiterDimming() {
        let editor = makeEditor()
        // "**bold** *italic* `code`"
        //  0123456789012345678901234
        editor.loadContent("**bold** *italic* `code`")
        activateBlock(0, in: editor)

        // ** at 0
        #expect(fgColor(at: 0, in: editor) == NSColor.tertiaryLabelColor)
        // * at 9
        #expect(fgColor(at: 9, in: editor) == NSColor.tertiaryLabelColor)
        // ` at 18
        #expect(fgColor(at: 18, in: editor) == NSColor.tertiaryLabelColor)
    }
}

// ============================================================================
// MARK: - Multi-block Document Integration
// ============================================================================

@Suite("Integration — Full Document")
struct FullDocumentIntegrationTests {

    @Test("Rich document: heading, paragraph, list, quote all render")
    @MainActor func richDocument() {
        let editor = makeEditor()
        editor.loadContent("# Title\nSome text\n- item\n> quote")

        // Make block 2 active (the list item)
        activateBlock(2, in: editor)

        // Block 0 (heading, inactive): "Title" with bold scaled font
        let h = displayText(for: 0, in: editor)
        #expect(h == "Title")
        let hf = font(at: editor.displayRanges[0].location, in: editor)!
        #expect(NSFontManager.shared.traits(of: hf).contains(.boldFontMask))

        // Block 1 (plain, inactive): "Some text"
        let p = displayText(for: 1, in: editor)
        #expect(p == "Some text")

        // Block 2 (list, active): "- item" (raw)
        let li = displayText(for: 2, in: editor)
        #expect(li == "- item")

        // Block 3 (quote, inactive): "quote" (stripped >)
        let q = displayText(for: 3, in: editor)
        #expect(q == "quote")
    }

    @Test("Type complete document from scratch, verify structure")
    @MainActor func typeFromScratch() {
        let editor = makeEditor()

        type("# My Doc", into: editor)
        pressEnter(in: editor)
        type("A paragraph.", into: editor)
        pressEnter(in: editor)
        type("- first", into: editor)
        pressEnter(in: editor)
        type("- second", into: editor)

        #expect(editor.blocks.count == 4)
        #expect(editor.rawSource == "# My Doc\nA paragraph.\n- first\n- second")
    }

    @Test("Paste markdown document, navigate blocks, verify rendering")
    @MainActor func pasteAndNavigate() {
        let editor = makeEditor()
        let md = "**Bold title**\n*Italic subtitle*\n`code block`\n~~deleted~~\n==highlight=="
        editor.loadContent(md)

        // Activate block 2 (code)
        activateBlock(2, in: editor)

        // Block 0 inactive: "Bold title" with bold
        #expect(displayText(for: 0, in: editor) == "Bold title")
        let bf = font(at: editor.displayRanges[0].location, in: editor)!
        #expect(NSFontManager.shared.traits(of: bf).contains(.boldFontMask))

        // Block 1 inactive: "Italic subtitle" with italic
        #expect(displayText(for: 1, in: editor) == "Italic subtitle")
        let itf = font(at: editor.displayRanges[1].location, in: editor)!
        #expect(NSFontManager.shared.traits(of: itf).contains(.italicFontMask))

        // Block 2 active: "`code block`" (raw)
        #expect(displayText(for: 2, in: editor) == "`code block`")

        // Block 3 inactive: "deleted" with strikethrough
        #expect(displayText(for: 3, in: editor) == "deleted")
        let a3 = attrs(at: editor.displayRanges[3].location, in: editor)
        #expect(a3[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)

        // Block 4 inactive: "highlight" with background
        #expect(displayText(for: 4, in: editor) == "highlight")
        let a4 = attrs(at: editor.displayRanges[4].location, in: editor)
        #expect(a4[.backgroundColor] != nil)
    }
}
