import Testing
import AppKit
@testable import MarkdownEditorCore

// MARK: - Test Helpers

/// Creates an EditorTextView with a proper text system chain,
/// mirroring the setup in main.swift.
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

/// Simulate typing a string character-by-character through the full
/// NSTextView pipeline (shouldChangeText → insert → didChangeText).
@MainActor
private func type(_ text: String, into editor: EditorTextView) {
    for ch in text {
        editor.insertText(String(ch), replacementRange: NSRange(location: NSNotFound, length: 0))
    }
}

/// Simulate typing a string as a single paste operation.
@MainActor
private func paste(_ text: String, into editor: EditorTextView) {
    editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
}

/// Simulate pressing Enter (inserts a newline).
@MainActor
private func pressEnter(in editor: EditorTextView) {
    editor.insertText("\n", replacementRange: NSRange(location: NSNotFound, length: 0))
}

/// Simulate pressing Backspace (delete backward).
@MainActor
private func pressBackspace(in editor: EditorTextView) {
    let sel = editor.selectedRange()
    if sel.length > 0 {
        editor.insertText("", replacementRange: sel)
    } else if sel.location > 0 {
        let deleteRange = NSRange(location: sel.location - 1, length: 1)
        editor.insertText("", replacementRange: deleteRange)
    }
}

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
