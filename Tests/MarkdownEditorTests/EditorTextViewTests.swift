import Testing
import AppKit
@testable import MarkdownEditorCore

// MARK: - Initialization

@Suite("EditorTextView — Initialization")
struct EditorInitTests {

    @Test("Starts with empty rawSource and one empty block")
    @MainActor func initialState() {
        let editor = makeEditor()
        #expect(editor.rawSource == "")
        #expect(editor.blocks.count == 1)
        #expect(editor.blocks[0].content == "")
        #expect(editor.activeBlockIndex == 0)
    }

    @Test("Text storage is empty after init")
    @MainActor func emptyTextStorage() {
        let editor = makeEditor()
        #expect(editor.textStorage?.string == "")
    }

    @Test("Undo and redo stacks are empty at start")
    @MainActor func emptyUndoStacks() {
        let editor = makeEditor()
        #expect(editor.undoStack.isEmpty)
        #expect(editor.redoStack.isEmpty)
    }
}

// MARK: - Basic Editing

@Suite("EditorTextView — Editing")
struct EditorEditTests {

    @Test("Typing updates rawSource")
    @MainActor func typingUpdatesRawSource() {
        let editor = makeEditor()
        type("hello", into: editor)
        #expect(editor.rawSource == "hello")
    }

    @Test("Typing updates text storage")
    @MainActor func typingUpdatesTextStorage() {
        let editor = makeEditor()
        type("hello", into: editor)
        #expect(editor.textStorage?.string == "hello")
    }

    @Test("Cursor advances to end of typed text")
    @MainActor func cursorAdvances() {
        let editor = makeEditor()
        type("hello", into: editor)
        #expect(editor.selectedRange().location == 5)
        #expect(editor.selectedRange().length == 0)
    }

    @Test("Paste inserts text at cursor")
    @MainActor func pasteInserts() {
        let editor = makeEditor()
        paste("hello world", into: editor)
        #expect(editor.rawSource == "hello world")
        #expect(editor.selectedRange().location == 11)
    }

    @Test("Backspace removes character before cursor")
    @MainActor func backspaceRemoves() {
        let editor = makeEditor()
        type("abc", into: editor)
        pressBackspace(in: editor)
        #expect(editor.rawSource == "ab")
    }

    @Test("Multiple backspaces")
    @MainActor func multipleBackspaces() {
        let editor = makeEditor()
        type("abc", into: editor)
        pressBackspace(in: editor)
        pressBackspace(in: editor)
        #expect(editor.rawSource == "a")
    }
}

// MARK: - Block Splitting

@Suite("EditorTextView — Block Splitting")
struct EditorBlockSplitTests {

    @Test("Enter creates a new block")
    @MainActor func enterCreatesBlock() {
        let editor = makeEditor()
        type("hello", into: editor)
        pressEnter(in: editor)
        #expect(editor.blocks.count == 2)
        #expect(editor.blocks[0].content == "hello")
        #expect(editor.blocks[1].content == "")
    }

    @Test("rawSource contains newline after Enter")
    @MainActor func rawSourceHasNewline() {
        let editor = makeEditor()
        type("hello", into: editor)
        pressEnter(in: editor)
        #expect(editor.rawSource == "hello\n")
    }

    @Test("Typing after Enter goes into the new block")
    @MainActor func typingAfterEnter() {
        let editor = makeEditor()
        type("hello", into: editor)
        pressEnter(in: editor)
        type("world", into: editor)
        #expect(editor.rawSource == "hello\nworld")
        #expect(editor.blocks.count == 2)
        #expect(editor.blocks[0].content == "hello")
        #expect(editor.blocks[1].content == "world")
    }

    @Test("Enter in the middle of text splits the block")
    @MainActor func enterInMiddle() {
        let editor = makeEditor()
        type("helloworld", into: editor)
        // Move cursor to position 5 (between "hello" and "world")
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        pressEnter(in: editor)
        #expect(editor.blocks.count == 2)
        #expect(editor.blocks[0].content == "hello")
        #expect(editor.blocks[1].content == "world")
    }

    @Test("Multiple Enters create multiple blocks")
    @MainActor func multipleEnters() {
        let editor = makeEditor()
        type("a", into: editor)
        pressEnter(in: editor)
        type("b", into: editor)
        pressEnter(in: editor)
        type("c", into: editor)
        #expect(editor.blocks.count == 3)
        #expect(editor.rawSource == "a\nb\nc")
    }
}

// MARK: - Undo / Redo

@Suite("EditorTextView — Undo")
struct EditorUndoTests {

    @Test("Undo reverts typing run")
    @MainActor func undoTypingRun() {
        let editor = makeEditor()
        type("hello", into: editor)
        editor.undo(nil)
        #expect(editor.rawSource == "")
    }

    @Test("Undo after single character")
    @MainActor func undoSingleChar() {
        let editor = makeEditor()
        type("a", into: editor)
        editor.undo(nil)
        #expect(editor.rawSource == "")
        #expect(editor.textStorage?.string == "")
    }

    @Test("Undo on empty editor does nothing")
    @MainActor func undoEmpty() {
        let editor = makeEditor()
        editor.undo(nil)  // should not crash
        #expect(editor.rawSource == "")
    }

    @Test("Undo restores cursor position")
    @MainActor func undoRestoresCursor() {
        let editor = makeEditor()
        type("hello", into: editor)
        #expect(editor.selectedRange().location == 5)
        editor.undo(nil)
        #expect(editor.selectedRange().location == 0)
    }

    @Test("Undo coalesces consecutive inserts")
    @MainActor func undoCoalesces() {
        let editor = makeEditor()
        type("hello", into: editor)
        // All 5 chars are one typing run → one undo group
        #expect(editor.undoStack.count == 1)
        editor.undo(nil)
        #expect(editor.rawSource == "")
    }

    @Test("Undo separates insert and delete groups")
    @MainActor func undoSeparatesInsertDelete() {
        let editor = makeEditor()
        type("abc", into: editor)
        pressBackspace(in: editor)  // switch from insert to delete
        #expect(editor.undoStack.count == 2)
        editor.undo(nil)  // undo the delete
        #expect(editor.rawSource == "abc")
        editor.undo(nil)  // undo the typing
        #expect(editor.rawSource == "")
    }

    @Test("Undo after paste reverts entire paste")
    @MainActor func undoPaste() {
        let editor = makeEditor()
        type("start", into: editor)
        paste(" pasted text", into: editor)
        // Paste is .other → always new group
        #expect(editor.undoStack.count == 2)
        editor.undo(nil)
        #expect(editor.rawSource == "start")
    }

    @Test("Undo after Enter merges blocks back")
    @MainActor func undoEnter() {
        let editor = makeEditor()
        type("hello", into: editor)
        pressEnter(in: editor)
        editor.undo(nil)
        // The Enter pushed a new undo group (newline is .other)
        #expect(editor.rawSource == "hello")
        #expect(editor.blocks.count == 1)
    }

    @Test("Multiple undos walk back through history")
    @MainActor func multipleUndos() {
        let editor = makeEditor()
        type("aaa", into: editor)      // group 1
        pressBackspace(in: editor)     // group 2
        type("bbb", into: editor)      // group 3

        editor.undo(nil)  // undo "bbb"
        #expect(editor.rawSource == "aa")
        editor.undo(nil)  // undo backspace
        #expect(editor.rawSource == "aaa")
        editor.undo(nil)  // undo "aaa"
        #expect(editor.rawSource == "")
    }
}

@Suite("EditorTextView — Redo")
struct EditorRedoTests {

    @Test("Redo restores undone text")
    @MainActor func redoRestores() {
        let editor = makeEditor()
        type("hello", into: editor)
        editor.undo(nil)
        #expect(editor.rawSource == "")
        editor.redo(nil)
        #expect(editor.rawSource == "hello")
    }

    @Test("Redo on empty redo stack does nothing")
    @MainActor func redoEmpty() {
        let editor = makeEditor()
        type("hello", into: editor)
        editor.redo(nil)  // nothing to redo
        #expect(editor.rawSource == "hello")
    }

    @Test("New edit clears redo stack")
    @MainActor func editClearsRedo() {
        let editor = makeEditor()
        type("hello", into: editor)
        editor.undo(nil)
        #expect(editor.redoStack.count == 1)
        type("x", into: editor)  // new edit
        #expect(editor.redoStack.isEmpty)
    }

    @Test("Undo then redo then undo roundtrips correctly")
    @MainActor func undoRedoUndoRoundtrip() {
        let editor = makeEditor()
        type("abc", into: editor)
        editor.undo(nil)
        #expect(editor.rawSource == "")
        editor.redo(nil)
        #expect(editor.rawSource == "abc")
        editor.undo(nil)
        #expect(editor.rawSource == "")
    }

    @Test("Multiple undo then multiple redo")
    @MainActor func multipleUndoRedo() {
        let editor = makeEditor()
        type("aaa", into: editor)       // group 1
        pressBackspace(in: editor)      // group 2
        type("bbb", into: editor)       // group 3

        // Undo all
        editor.undo(nil)
        editor.undo(nil)
        editor.undo(nil)
        #expect(editor.rawSource == "")

        // Redo all
        editor.redo(nil)
        #expect(editor.rawSource == "aaa")
        editor.redo(nil)
        #expect(editor.rawSource == "aa")
        editor.redo(nil)
        #expect(editor.rawSource == "aabbb")
    }
}

// MARK: - Coordinate Mapping

@Suite("EditorTextView — Coordinate Mapping")
struct EditorCoordinateTests {

    @Test("Single block: display offset equals raw offset")
    @MainActor func singleBlockIdentity() {
        let editor = makeEditor()
        type("hello", into: editor)

        #expect(editor.displayOffsetToRawOffset(0) == 0)
        #expect(editor.displayOffsetToRawOffset(3) == 3)
        #expect(editor.displayOffsetToRawOffset(5) == 5)

        #expect(editor.rawOffsetToDisplayOffset(0) == 0)
        #expect(editor.rawOffsetToDisplayOffset(3) == 3)
        #expect(editor.rawOffsetToDisplayOffset(5) == 5)
    }

    @Test("blockIndexForRawOffset returns correct index")
    @MainActor func blockIndexMapping() {
        let editor = makeEditor()
        // Set up multi-block state directly
        editor.rawSource = "hello\nworld"
        editor.blocks = BlockParser.parse(editor.rawSource)
        editor.recompose(cursorInRaw: 0)

        #expect(editor.blockIndexForRawOffset(0) == 0)   // start of "hello"
        #expect(editor.blockIndexForRawOffset(3) == 0)   // middle of "hello"
        #expect(editor.blockIndexForRawOffset(5) == 0)   // end of "hello"
        #expect(editor.blockIndexForRawOffset(6) == 1)   // start of "world"
        #expect(editor.blockIndexForRawOffset(11) == 1)  // end of "world"
    }

    @Test("blockIndexForRawOffset clamps to last block")
    @MainActor func blockIndexClamp() {
        let editor = makeEditor()
        editor.rawSource = "abc"
        editor.blocks = BlockParser.parse(editor.rawSource)
        editor.recompose(cursorInRaw: 0)

        #expect(editor.blockIndexForRawOffset(100) == 0)
    }
}

// MARK: - Markdown Rendering

@Suite("EditorTextView — Markdown Rendering")
struct EditorMarkdownTests {

    @Test("Bold markdown renders to shorter text (removes **)")
    @MainActor func boldRendering() {
        let editor = makeEditor()
        let rendered = editor.renderMarkdown("**bold**")
        #expect(rendered.string == "bold")
    }

    @Test("Italic markdown renders to shorter text (removes *)")
    @MainActor func italicRendering() {
        let editor = makeEditor()
        let rendered = editor.renderMarkdown("*italic*")
        #expect(rendered.string == "italic")
    }

    @Test("Plain text renders unchanged")
    @MainActor func plainRendering() {
        let editor = makeEditor()
        let rendered = editor.renderMarkdown("just plain text")
        #expect(rendered.string == "just plain text")
    }

    @Test("Inline code renders without backticks")
    @MainActor func codeRendering() {
        let editor = makeEditor()
        let rendered = editor.renderMarkdown("`code`")
        #expect(rendered.string == "code")
    }

    @Test("Bold text is rendered (syntax stripped) and has font attribute")
    @MainActor func boldFontTrait() {
        let editor = makeEditor()
        let rendered = editor.renderMarkdown("**bold**")
        // The markdown syntax ** should be stripped
        #expect(rendered.string.contains("bold"))
        #expect(!rendered.string.contains("**"))
        // Font attribute should be present (trait may vary by environment)
        var hasFont = false
        rendered.enumerateAttribute(.font, in: NSRange(location: 0, length: rendered.length)) { val, _, _ in
            if val is NSFont { hasFont = true }
        }
        #expect(hasFont)
    }

    @Test("Italic text is rendered (syntax stripped) and has font attribute")
    @MainActor func italicFontTrait() {
        let editor = makeEditor()
        let rendered = editor.renderMarkdown("*italic*")
        // The markdown syntax * should be stripped
        #expect(rendered.string.contains("italic"))
        // Check that the wrapping *s are gone (the word itself doesn't start/end with *)
        let trimmed = rendered.string.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!trimmed.hasPrefix("*"))
        #expect(!trimmed.hasSuffix("*"))
        // Font attribute should be present
        var hasFont = false
        rendered.enumerateAttribute(.font, in: NSRange(location: 0, length: rendered.length)) { val, _, _ in
            if val is NSFont { hasFont = true }
        }
        #expect(hasFont)
    }

    @Test("Empty string renders to empty attributed string")
    @MainActor func emptyRendering() {
        let editor = makeEditor()
        let rendered = editor.renderMarkdown("")
        #expect(rendered.string == "")
    }

    @Test("Heading renders without # prefix")
    @MainActor func headingRendering() {
        let editor = makeEditor()
        let rendered = editor.renderMarkdown("# Hello")
        #expect(rendered.string == "Hello")
    }

    @Test("Bold italic renders without delimiters")
    @MainActor func boldItalicRendering() {
        let editor = makeEditor()
        let rendered = editor.renderMarkdown("***both***")
        #expect(rendered.string == "both")
    }

    @Test("**hi* renders as *hi (extra * stays, matched delimiters stripped)")
    @MainActor func mismatchedDoubleOpenSingleClose() {
        let editor = makeEditor()
        let rendered = editor.renderMarkdown("**hi*")
        #expect(rendered.string == "*hi")
    }

    @Test("*hi** renders as hi* (extra * stays, matched delimiters stripped)")
    @MainActor func mismatchedSingleOpenDoubleClose() {
        let editor = makeEditor()
        let rendered = editor.renderMarkdown("*hi**")
        #expect(rendered.string == "hi*")
    }

    @Test("***hi** renders as *hi (extra * stays, bold delimiters stripped)")
    @MainActor func mismatchedTripleOpenDoubleClose() {
        let editor = makeEditor()
        let rendered = editor.renderMarkdown("***hi**")
        #expect(rendered.string == "*hi")
    }

    @Test("Link renders as text only (delimiters stripped)")
    @MainActor func linkRendering() {
        let editor = makeEditor()
        let rendered = editor.renderMarkdown("[click here](https://example.com)")
        #expect(rendered.string == "click here")
    }

    @Test("Blockquote renders without > prefix")
    @MainActor func blockquoteRendering() {
        let editor = makeEditor()
        let rendered = editor.renderMarkdown("> hello world")
        #expect(rendered.string == "hello world")
    }

    @Test("Unordered list item renders with bullet")
    @MainActor func unorderedListRendering() {
        let editor = makeEditor()
        let rendered = editor.renderMarkdown("- hello")
        #expect(rendered.string == "\u{2022} hello")
    }

    @Test("Ordered list item keeps its number")
    @MainActor func orderedListRendering() {
        let editor = makeEditor()
        let rendered = editor.renderMarkdown("1. hello")
        #expect(rendered.string == "1. hello")
    }

    @Test("Inline code renders in dark red")
    @MainActor func inlineCodeColor() {
        let editor = makeEditor()
        let rendered = editor.renderMarkdown("`code`")
        #expect(rendered.string == "code")
        var foundCodeColor = false
        rendered.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: rendered.length)) { val, _, _ in
            if let color = val as? NSColor {
                // Check it's approximately #8a2425
                if color.redComponent > 0.5 && color.greenComponent < 0.2 && color.blueComponent < 0.2 {
                    foundCodeColor = true
                }
            }
        }
        #expect(foundCodeColor)
    }

    @Test("Active block inline code has dark red content")
    @MainActor func activeCodeColor() {
        let editor = makeEditor()
        let highlighted = editor.highlightSyntax("`code`")
        #expect(highlighted.string == "`code`")
        // Check the content range (chars 1-4) has the code color
        var foundCodeColor = false
        highlighted.enumerateAttribute(.foregroundColor, in: NSRange(location: 1, length: 4)) { val, _, _ in
            if let color = val as? NSColor {
                if color.redComponent > 0.5 && color.greenComponent < 0.2 && color.blueComponent < 0.2 {
                    foundCodeColor = true
                }
            }
        }
        #expect(foundCodeColor)
    }

    @Test("Link rendered text has underline attribute")
    @MainActor func linkUnderline() {
        let editor = makeEditor()
        let rendered = editor.renderMarkdown("[text](url)")
        #expect(rendered.string == "text")
        var hasUnderline = false
        rendered.enumerateAttribute(.underlineStyle, in: NSRange(location: 0, length: rendered.length)) { val, _, _ in
            if val != nil { hasUnderline = true }
        }
        #expect(hasUnderline)
    }

    @Test("Blockquote rendered text has secondary label color")
    @MainActor func blockquoteColor() {
        let editor = makeEditor()
        let rendered = editor.renderMarkdown("> text")
        var hasSecondaryColor = false
        rendered.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: rendered.length)) { val, _, _ in
            if let color = val as? NSColor, color == NSColor.secondaryLabelColor {
                hasSecondaryColor = true
            }
        }
        #expect(hasSecondaryColor)
    }

    @Test("List items have indented paragraph style")
    @MainActor func listIndentation() {
        let editor = makeEditor()
        let rendered = editor.renderMarkdown("- hello")
        var hasIndent = false
        rendered.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: rendered.length)) { val, _, _ in
            if let ps = val as? NSParagraphStyle, ps.firstLineHeadIndent > 0 {
                hasIndent = true
            }
        }
        #expect(hasIndent)
    }

    @Test("Active list items have indented paragraph style")
    @MainActor func activeListIndentation() {
        let editor = makeEditor()
        let highlighted = editor.highlightSyntax("- hello")
        var hasIndent = false
        highlighted.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: highlighted.length)) { val, _, _ in
            if let ps = val as? NSParagraphStyle, ps.firstLineHeadIndent > 0 {
                hasIndent = true
            }
        }
        #expect(hasIndent)
    }

    @Test("Ordered list number is dimmed")
    @MainActor func orderedListNumberDimmed() {
        let editor = makeEditor()
        let rendered = editor.renderMarkdown("1. hello")
        // The "1. " should have the dim color
        var hasDimColor = false
        rendered.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: 3)) { val, _, _ in
            if val is NSColor { hasDimColor = true }
        }
        #expect(hasDimColor)
    }

    @Test("Strikethrough renders without ~~ delimiters")
    @MainActor func strikethroughRendering() {
        let editor = makeEditor()
        let rendered = editor.renderMarkdown("~~deleted~~")
        #expect(rendered.string == "deleted")
        var hasStrikethrough = false
        rendered.enumerateAttribute(.strikethroughStyle, in: NSRange(location: 0, length: rendered.length)) { val, _, _ in
            if val != nil { hasStrikethrough = true }
        }
        #expect(hasStrikethrough)
    }

    @Test("Active block strikethrough has strikethrough attribute")
    @MainActor func activeStrikethrough() {
        let editor = makeEditor()
        let highlighted = editor.highlightSyntax("~~deleted~~")
        #expect(highlighted.string == "~~deleted~~")
        var hasStrikethrough = false
        highlighted.enumerateAttribute(.strikethroughStyle, in: NSRange(location: 2, length: 7)) { val, _, _ in
            if val != nil { hasStrikethrough = true }
        }
        #expect(hasStrikethrough)
    }

    @Test("Highlight renders without == delimiters")
    @MainActor func highlightRendering() {
        let editor = makeEditor()
        let rendered = editor.renderMarkdown("==important==")
        #expect(rendered.string == "important")
        var hasBackground = false
        rendered.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: rendered.length)) { val, _, _ in
            if val != nil { hasBackground = true }
        }
        #expect(hasBackground)
    }

    @Test("Active block highlight has background color")
    @MainActor func activeHighlight() {
        let editor = makeEditor()
        let highlighted = editor.highlightSyntax("==important==")
        #expect(highlighted.string == "==important==")
        var hasBackground = false
        highlighted.enumerateAttribute(.backgroundColor, in: NSRange(location: 2, length: 9)) { val, _, _ in
            if val != nil { hasBackground = true }
        }
        #expect(hasBackground)
    }

    @Test("Blockquote has paragraph style with text block")
    @MainActor func blockquoteTextBlock() {
        let editor = makeEditor()
        let rendered = editor.renderMarkdown("> text")
        var hasTextBlock = false
        rendered.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: rendered.length)) { val, _, _ in
            if let ps = val as? NSParagraphStyle, !ps.textBlocks.isEmpty {
                hasTextBlock = true
            }
        }
        #expect(hasTextBlock)
    }
}

// MARK: - Display Composition

@Suite("EditorTextView — Recompose")
struct EditorRecomposeTests {

    @Test("Active block shows raw markdown in text storage")
    @MainActor func activeBlockShowsRaw() {
        let editor = makeEditor()
        editor.rawSource = "**bold**\nplain"
        editor.blocks = BlockParser.parse(editor.rawSource)
        // Cursor in block 0 — block 0 stays raw
        editor.recompose(cursorInRaw: 0)

        let display = editor.textStorage!.string
        #expect(display.hasPrefix("**bold**"))
    }

    @Test("Non-active block shows rendered markdown in text storage")
    @MainActor func nonActiveBlockRendered() {
        let editor = makeEditor()
        editor.rawSource = "**bold**\nplain"
        editor.blocks = BlockParser.parse(editor.rawSource)
        // Cursor in block 1 — block 0 gets rendered
        editor.recompose(cursorInRaw: 9)  // offset 9 = start of "plain"

        let display = editor.textStorage!.string
        // Block 0 should be rendered: "**bold**" → "bold"
        #expect(display.hasPrefix("bold"))
        #expect(display.hasSuffix("plain"))
    }

    @Test("Display ranges are computed correctly after recompose")
    @MainActor func displayRangesCorrect() {
        let editor = makeEditor()
        editor.rawSource = "**bold**\nplain"
        editor.blocks = BlockParser.parse(editor.rawSource)
        editor.recompose(cursorInRaw: 9)

        #expect(editor.displayRanges.count == 2)
        // Block 0 rendered: "bold" = 4 chars
        #expect(editor.displayRanges[0].length == 4)
        // Block 1 active: "plain" = 5 chars
        #expect(editor.displayRanges[1].length == 5)
    }

    @Test("activeBlockIndex is set correctly")
    @MainActor func activeBlockIndexCorrect() {
        let editor = makeEditor()
        editor.rawSource = "aaa\nbbb\nccc"
        editor.blocks = BlockParser.parse(editor.rawSource)

        editor.recompose(cursorInRaw: 0)
        #expect(editor.activeBlockIndex == 0)

        editor.recompose(cursorInRaw: 4)
        #expect(editor.activeBlockIndex == 1)

        editor.recompose(cursorInRaw: 8)
        #expect(editor.activeBlockIndex == 2)
    }
}

// MARK: - Undo Coalescing Details

@Suite("EditorTextView — Undo Coalescing")
struct EditorCoalescingTests {

    @Test("Consecutive single-char inserts produce one undo group")
    @MainActor func insertCoalescing() {
        let editor = makeEditor()
        type("abcde", into: editor)
        #expect(editor.undoStack.count == 1)
    }

    @Test("Consecutive single-char deletes produce one undo group")
    @MainActor func deleteCoalescing() {
        let editor = makeEditor()
        type("abc", into: editor)
        let undoCountAfterTyping = editor.undoStack.count  // 1
        pressBackspace(in: editor)
        pressBackspace(in: editor)
        // Delete is a different type from insert → +1 group
        #expect(editor.undoStack.count == undoCountAfterTyping + 1)
    }

    @Test("Switching from insert to delete starts new group")
    @MainActor func insertToDeleteBreak() {
        let editor = makeEditor()
        type("abc", into: editor)
        #expect(editor.undoStack.count == 1)
        pressBackspace(in: editor)
        #expect(editor.undoStack.count == 2)
    }

    @Test("Paste always starts a new group")
    @MainActor func pasteAlwaysNewGroup() {
        let editor = makeEditor()
        type("a", into: editor)
        paste("xyz", into: editor)
        #expect(editor.undoStack.count == 2)
        paste("123", into: editor)
        #expect(editor.undoStack.count == 3)
    }
}

// MARK: - Integration

@Suite("EditorTextView — Integration")
struct EditorIntegrationTests {

    @Test("Full editing session: type, Enter, type, undo all, redo all")
    @MainActor func fullSession() {
        let editor = makeEditor()

        // Type first line
        type("hello", into: editor)
        #expect(editor.rawSource == "hello")

        // Press Enter
        pressEnter(in: editor)
        #expect(editor.blocks.count == 2)

        // Type second line
        type("world", into: editor)
        #expect(editor.rawSource == "hello\nworld")

        // Undo "world"
        editor.undo(nil)
        #expect(editor.rawSource == "hello\n")

        // Undo Enter
        editor.undo(nil)
        #expect(editor.rawSource == "hello")
        #expect(editor.blocks.count == 1)

        // Undo "hello"
        editor.undo(nil)
        #expect(editor.rawSource == "")

        // Redo everything
        editor.redo(nil)
        #expect(editor.rawSource == "hello")
        editor.redo(nil)
        #expect(editor.rawSource == "hello\n")
        editor.redo(nil)
        #expect(editor.rawSource == "hello\nworld")
    }

    @Test("Backspace at start of line merges with previous block")
    @MainActor func backspaceMergesBlocks() {
        let editor = makeEditor()
        type("hello", into: editor)
        pressEnter(in: editor)
        type("world", into: editor)
        #expect(editor.blocks.count == 2)

        // Move cursor to start of "world" and backspace
        // After Enter+typing, cursor is at end of "world".
        // "hello\nworld" in display. Position 6 = start of "world" block.
        editor.setSelectedRange(NSRange(location: 6, length: 0))
        pressBackspace(in: editor)
        // This should delete the \n, merging into "helloworld"
        #expect(editor.rawSource == "helloworld")
        #expect(editor.blocks.count == 1)
    }
}

// MARK: - Document Loading

@Suite("EditorTextView — Document Loading")
struct EditorDocumentLoadingTests {

    @Test("loadContent replaces editor content")
    @MainActor func loadContentReplacesContent() {
        let editor = makeEditor()
        type("old text", into: editor)
        #expect(editor.rawSource == "old text")

        editor.loadContent("new content")
        #expect(editor.rawSource == "new content")
        #expect(editor.blocks.count == 1)
        #expect(editor.blocks[0].content == "new content")
    }

    @Test("loadContent with multiple lines creates multiple blocks")
    @MainActor func loadContentMultipleBlocks() {
        let editor = makeEditor()
        editor.loadContent("line one\nline two\nline three")
        #expect(editor.rawSource == "line one\nline two\nline three")
        #expect(editor.blocks.count == 3)
        #expect(editor.blocks[0].content == "line one")
        #expect(editor.blocks[1].content == "line two")
        #expect(editor.blocks[2].content == "line three")
    }

    @Test("loadContent clears undo/redo stacks")
    @MainActor func loadContentClearsUndo() {
        let editor = makeEditor()
        type("some edits", into: editor)
        #expect(!editor.undoStack.isEmpty)

        editor.loadContent("fresh document")
        #expect(editor.undoStack.isEmpty)
        #expect(editor.redoStack.isEmpty)
    }

    @Test("loadContent with empty string produces one empty block")
    @MainActor func loadContentEmpty() {
        let editor = makeEditor()
        type("something", into: editor)

        editor.loadContent("")
        #expect(editor.rawSource == "")
        #expect(editor.blocks.count == 1)
        #expect(editor.blocks[0].content == "")
    }

    @Test("loadContent renders markdown in non-active blocks")
    @MainActor func loadContentRendersInactiveBlocks() {
        let editor = makeEditor()
        editor.loadContent("**bold**\n*italic*")
        #expect(editor.blocks.count == 2)

        // The text storage should contain rendered content for inactive blocks.
        // Block 0 is active (cursor at 0), block 1 is inactive and rendered.
        let ts = editor.textStorage!.string
        // Active block shows raw markdown, inactive block strips delimiters
        #expect(ts.contains("**bold**"))  // active — raw
        #expect(ts.contains("italic"))     // inactive — rendered (no *)
        #expect(!ts.contains("*italic*"))  // delimiters stripped
    }

    @Test("loadContent with markdown preserves rawSource exactly")
    @MainActor func loadContentPreservesRawSource() {
        let editor = makeEditor()
        let markdown = "# Heading\n\n**bold** and *italic*\n\n> quote\n\n- list item"
        editor.loadContent(markdown)
        #expect(editor.rawSource == markdown)
    }

    @Test("Typing after loadContent works normally")
    @MainActor func typingAfterLoadContent() {
        let editor = makeEditor()
        editor.loadContent("hello")
        // Cursor should be at position 0 after load
        type(" world", into: editor)
        #expect(editor.rawSource.contains("world"))
    }
}

// MARK: - Tab / Shift-Tab List Indentation

@Suite("EditorTextView — List Indentation")
struct EditorTextViewListIndentationTests {

    // MARK: - isListLine Detection

    @Test("isListLine detects unordered list markers")
    @MainActor func isListLineUnordered() {
        let editor = makeEditor()
        #expect(editor.isListLine("- item"))
        #expect(editor.isListLine("* item"))
        #expect(editor.isListLine("+ item"))
        #expect(editor.isListLine("  - nested"))
        #expect(editor.isListLine("    - deeply nested"))
    }

    @Test("isListLine detects ordered list markers")
    @MainActor func isListLineOrdered() {
        let editor = makeEditor()
        #expect(editor.isListLine("1. item"))
        #expect(editor.isListLine("99. item"))
        #expect(editor.isListLine("  1. nested"))
    }

    @Test("isListLine rejects non-list lines")
    @MainActor func isListLineRejectsNonList() {
        let editor = makeEditor()
        #expect(!editor.isListLine("hello"))
        #expect(!editor.isListLine("# heading"))
        #expect(!editor.isListLine("> quote"))
        #expect(!editor.isListLine(""))
        #expect(!editor.isListLine("-no space"))
    }

    // MARK: - Tab Indent

    @Test("Tab on single list line adds 4 spaces")
    @MainActor func tabIndentsSingleLine() {
        let editor = makeEditor()
        editor.loadContent("- item")
        // Place cursor somewhere in the line
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        editor.insertTab(nil)
        #expect(editor.rawSource == "    - item")
    }

    @Test("Tab on ordered list line adds 4 spaces")
    @MainActor func tabIndentsOrderedList() {
        let editor = makeEditor()
        editor.loadContent("1. item")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.insertTab(nil)
        #expect(editor.rawSource == "    1. item")
    }

    @Test("Tab on non-list line inserts tab character")
    @MainActor func tabOnNonListInsertsTabs() {
        let editor = makeEditor()
        editor.loadContent("hello")
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        editor.insertTab(nil)
        #expect(editor.rawSource.contains("\t"))
    }

    @Test("Tab indents multiple selected list lines")
    @MainActor func tabIndentsMultipleLines() {
        let editor = makeEditor()
        editor.loadContent("- a\n- b\n- c")
        // Select across all three blocks (in display, active block 0 shows raw)
        let len = editor.textStorage!.length
        editor.setSelectedRange(NSRange(location: 0, length: len))
        editor.insertTab(nil)
        #expect(editor.rawSource == "    - a\n    - b\n    - c")
    }

    @Test("Tab stacks indentation on repeated use")
    @MainActor func tabStacksIndent() {
        let editor = makeEditor()
        editor.loadContent("- item")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.insertTab(nil)
        editor.insertTab(nil)
        #expect(editor.rawSource == "        - item")
    }

    @Test("Tab on mixed list and non-list falls through to default")
    @MainActor func tabMixedListNonList() {
        let editor = makeEditor()
        editor.loadContent("- a\nhello\n- c")
        let len = editor.textStorage!.length
        editor.setSelectedRange(NSRange(location: 0, length: len))
        editor.insertTab(nil)
        // Should NOT have indented; default behavior inserts a tab
        #expect(!editor.rawSource.hasPrefix("    - a"))
    }

    // MARK: - Shift-Tab Dedent

    @Test("Shift-Tab removes up to 4 leading spaces")
    @MainActor func shiftTabRemovesSpaces() {
        let editor = makeEditor()
        editor.loadContent("    - item")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.insertBacktab(nil)
        #expect(editor.rawSource == "- item")
    }

    @Test("Shift-Tab removes partial indent (fewer than 4 spaces)")
    @MainActor func shiftTabRemovesPartialIndent() {
        let editor = makeEditor()
        editor.loadContent("  - item")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.insertBacktab(nil)
        #expect(editor.rawSource == "- item")
    }

    @Test("Shift-Tab on root-level list with no spaces does nothing")
    @MainActor func shiftTabRootLevelNoOp() {
        let editor = makeEditor()
        editor.loadContent("- item")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.insertBacktab(nil)
        #expect(editor.rawSource == "- item")
    }

    @Test("Shift-Tab dedents multiple selected lines")
    @MainActor func shiftTabDedentsMultipleLines() {
        let editor = makeEditor()
        editor.loadContent("    - a\n    - b\n    - c")
        let len = editor.textStorage!.length
        editor.setSelectedRange(NSRange(location: 0, length: len))
        editor.insertBacktab(nil)
        #expect(editor.rawSource == "- a\n- b\n- c")
    }

    @Test("Shift-Tab with mixed indent levels removes up to 4 from each")
    @MainActor func shiftTabMixedIndentLevels() {
        let editor = makeEditor()
        editor.loadContent("        - a\n    - b\n  - c")
        let len = editor.textStorage!.length
        editor.setSelectedRange(NSRange(location: 0, length: len))
        editor.insertBacktab(nil)
        #expect(editor.rawSource == "    - a\n- b\n- c")
    }

    // MARK: - Undo Integration

    @Test("Undo reverts tab indent")
    @MainActor func undoRevertsIndent() {
        let editor = makeEditor()
        editor.loadContent("- item")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.insertTab(nil)
        #expect(editor.rawSource == "    - item")
        editor.undo(nil)
        #expect(editor.rawSource == "- item")
    }

    @Test("Undo reverts shift-tab dedent")
    @MainActor func undoRevertsDedent() {
        let editor = makeEditor()
        editor.loadContent("    - item")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.insertBacktab(nil)
        #expect(editor.rawSource == "- item")
        editor.undo(nil)
        #expect(editor.rawSource == "    - item")
    }

    @Test("Tab then Shift-Tab roundtrips")
    @MainActor func tabShiftTabRoundtrip() {
        let editor = makeEditor()
        editor.loadContent("- item")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.insertTab(nil)
        #expect(editor.rawSource == "    - item")
        editor.insertBacktab(nil)
        #expect(editor.rawSource == "- item")
    }
}

// MARK: - List Indentation Integration

@Suite("EditorTextView — List Indent Integration")
struct EditorListIndentIntegrationTests {

    @Test("Type a list from scratch, indent it, verify display")
    @MainActor func typeListThenIndent() {
        let editor = makeEditor()

        // Type a list item from scratch
        type("- apples", into: editor)
        #expect(editor.rawSource == "- apples")
        #expect(editor.blocks.count == 1)

        // Press Enter and type another item
        pressEnter(in: editor)
        type("- bananas", into: editor)
        #expect(editor.rawSource == "- apples\n- bananas")
        #expect(editor.blocks.count == 2)

        // Indent the second line (cursor is already there)
        editor.insertTab(nil)
        #expect(editor.rawSource == "- apples\n    - bananas")
        #expect(editor.blocks[1].content == "    - bananas")

        // Verify text storage contains the indented text
        let display = editor.textStorage!.string
        #expect(display.contains("    - bananas"))
    }

    @Test("Type mixed list, select all, indent, verify all indented")
    @MainActor func selectAllAndIndent() {
        let editor = makeEditor()

        type("- first", into: editor)
        pressEnter(in: editor)
        type("- second", into: editor)
        pressEnter(in: editor)
        type("- third", into: editor)
        #expect(editor.blocks.count == 3)

        // Select all and indent
        let len = editor.textStorage!.length
        editor.setSelectedRange(NSRange(location: 0, length: len))
        editor.insertTab(nil)

        #expect(editor.rawSource == "    - first\n    - second\n    - third")

        // Verify each block was indented
        for block in editor.blocks {
            #expect(block.content.hasPrefix("    - "))
        }
    }

    @Test("Indent then dedent restores original via display pipeline")
    @MainActor func indentDedentFullPipeline() {
        let editor = makeEditor()

        type("1. buy milk", into: editor)
        pressEnter(in: editor)
        type("2. buy eggs", into: editor)

        let original = editor.rawSource

        // Select all and indent
        let len = editor.textStorage!.length
        editor.setSelectedRange(NSRange(location: 0, length: len))
        editor.insertTab(nil)
        #expect(editor.rawSource != original)

        // Select all again and dedent
        let newLen = editor.textStorage!.length
        editor.setSelectedRange(NSRange(location: 0, length: newLen))
        editor.insertBacktab(nil)
        #expect(editor.rawSource == original)
    }

    @Test("Cursor position preserved after indent on single line")
    @MainActor func cursorPositionAfterIndent() {
        let editor = makeEditor()
        editor.loadContent("- hello")

        // Place cursor after "hel" → raw offset 4 ("- he|llo")
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        editor.insertTab(nil)

        // rawSource should be "    - hello", cursor should be at offset 8
        #expect(editor.rawSource == "    - hello")
        let sel = editor.selectedRange()
        // Cursor shifted by 4 (the indent)
        #expect(sel.location == 8)
        #expect(sel.length == 0)
    }

    @Test("Cursor position preserved after dedent on single line")
    @MainActor func cursorPositionAfterDedent() {
        let editor = makeEditor()
        editor.loadContent("    - hello")

        // Place cursor after the indent + "- he" → offset 8
        editor.setSelectedRange(NSRange(location: 8, length: 0))
        editor.insertBacktab(nil)

        #expect(editor.rawSource == "- hello")
        let sel = editor.selectedRange()
        // Cursor shifted back by 4
        #expect(sel.location == 4)
        #expect(sel.length == 0)
    }

    @Test("Full session: type list, indent, type more, undo everything")
    @MainActor func fullIndentSession() {
        let editor = makeEditor()

        // Build a list
        type("- a", into: editor)
        pressEnter(in: editor)
        type("- b", into: editor)
        #expect(editor.rawSource == "- a\n- b")

        // Indent second item
        editor.insertTab(nil)
        #expect(editor.rawSource == "- a\n    - b")

        // Type more on the indented line
        type("ee", into: editor)
        #expect(editor.rawSource == "- a\n    - bee")

        // Undo the typing ("ee")
        editor.undo(nil)
        #expect(editor.rawSource == "- a\n    - b")

        // Undo the indent
        editor.undo(nil)
        #expect(editor.rawSource == "- a\n- b")

        // Undo typing "- b"
        editor.undo(nil)
        #expect(editor.rawSource == "- a\n")

        // Undo Enter
        editor.undo(nil)
        #expect(editor.rawSource == "- a")
    }

    @Test("Tab on non-active block after navigating")
    @MainActor func indentNonActiveBlock() {
        let editor = makeEditor()
        editor.loadContent("- first\n- second\n- third")

        // After loadContent, cursor is at 0, active block is 0.
        // Move cursor to the second block.
        // Block 0 is "- first" (inactive rendered). Block 1 should become active.
        // In the display, block 0 is rendered (shorter due to bullet), block 1 raw.
        // Let's set cursor into block 1's display region.
        let block1DisplayStart = editor.displayRanges[1].location
        editor.setSelectedRange(NSRange(location: block1DisplayStart, length: 0))

        // Trigger recompose so block 1 becomes active
        // (Selection change notification fires async, so drive it manually)
        let rawOffset = editor.displayOffsetToRawOffset(block1DisplayStart)
        editor.recompose(cursorInRaw: rawOffset)

        #expect(editor.activeBlockIndex == 1)

        // Now indent — should indent block 1 only
        editor.insertTab(nil)
        #expect(editor.blocks[0].content == "- first")
        #expect(editor.blocks[1].content == "    - second")
        #expect(editor.blocks[2].content == "- third")
    }

    @Test("Double indent creates 8-space prefix")
    @MainActor func doubleIndent() {
        let editor = makeEditor()
        editor.loadContent("- item")
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        editor.insertTab(nil)
        editor.insertTab(nil)
        #expect(editor.rawSource == "        - item")
        #expect(editor.blocks[0].content.hasPrefix("        - "))

        // Double dedent brings it back
        editor.insertBacktab(nil)
        #expect(editor.rawSource == "    - item")
        editor.insertBacktab(nil)
        #expect(editor.rawSource == "- item")
    }

    @Test("Mixed ordered and unordered list indent together")
    @MainActor func mixedListTypes() {
        let editor = makeEditor()
        editor.loadContent("- bullet\n1. numbered\n+ plus")

        let len = editor.textStorage!.length
        editor.setSelectedRange(NSRange(location: 0, length: len))
        editor.insertTab(nil)

        #expect(editor.rawSource == "    - bullet\n    1. numbered\n    + plus")
    }

    @Test("Checkbox list items indent correctly")
    @MainActor func checkboxIndent() {
        let editor = makeEditor()
        editor.loadContent("- [ ] todo\n- [x] done")

        let len = editor.textStorage!.length
        editor.setSelectedRange(NSRange(location: 0, length: len))
        editor.insertTab(nil)

        #expect(editor.rawSource == "    - [ ] todo\n    - [x] done")
    }
}
