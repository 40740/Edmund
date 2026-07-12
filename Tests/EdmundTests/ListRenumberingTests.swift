import Testing
import AppKit
@testable import EdmundCore

// MARK: - Ordered List Renumbering
//
// Inserting/deleting an ordered list item should renumber the contiguous
// run of siblings at the same nesting depth, preserving the run's starting
// number, and leaving other depths / unrelated lists untouched.

@Suite("EditorTextView — List Renumbering")
struct ListRenumberingTests {

    @Test("Whole-line delete of a mid-list item renumbers the tail")
    @MainActor func wholeLineDeleteRenumbers() {
        let editor = makeEditor()
        editor.loadContent("1. a\n2. b\n3. c\n")
        // Select the full "2. b\n" line.
        let deleteRange = NSRange(location: 5, length: 5)
        editor.setSelectedRange(deleteRange)
        editor.insertText("", replacementRange: deleteRange)
        #expect(editor.rawSource == "1. a\n2. c\n")
    }

    @Test("Backspace-merge into the previous item renumbers the tail")
    @MainActor func backspaceMergeRenumbers() {
        let editor = makeEditor()
        editor.loadContent("1. a\n2. b\n3. c")
        // Caret at the start of "2. b" (offset 5): one backspace deletes the
        // preceding "\n", merging it onto "1. a"'s line — leaving "3. c" as
        // the second item in the run, which should renumber to "2. c".
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        pressBackspace(in: editor)
        #expect(editor.rawSource == "1. a2. b\n2. c")
    }

    @Test("Deleting an item preserves the run's starting number")
    @MainActor func startNumberPreserved() {
        let editor = makeEditor()
        editor.loadContent("5. a\n6. b\n7. c\n")
        let deleteRange = NSRange(location: 5, length: 5)
        editor.setSelectedRange(deleteRange)
        editor.insertText("", replacementRange: deleteRange)
        #expect(editor.rawSource == "5. a\n6. c\n")
    }

    @Test("Editing the top level leaves a nested ordered run untouched")
    @MainActor func nestedLevelUntouchedWhenEditingParent() {
        let editor = makeEditor()
        editor.loadContent("1. a\n   1. x\n   2. y\n2. b\n3. c\n")
        // Delete the top-level "2. b\n" line.
        let range = (editor.rawSource as NSString).range(of: "2. b\n")
        editor.setSelectedRange(range)
        editor.insertText("", replacementRange: range)
        #expect(editor.rawSource == "1. a\n   1. x\n   2. y\n2. c\n")
    }

    @Test("Editing a nested run leaves the parent level untouched")
    @MainActor func parentLevelUntouchedWhenEditingNested() {
        let editor = makeEditor()
        editor.loadContent("1. a\n   1. x\n   2. y\n   3. z\n2. b\n")
        let range = (editor.rawSource as NSString).range(of: "   2. y\n")
        editor.setSelectedRange(range)
        editor.insertText("", replacementRange: range)
        #expect(editor.rawSource == "1. a\n   1. x\n   2. z\n2. b\n")
    }

    @Test("Deleting a bullet item does not trigger ordered renumbering")
    @MainActor func unorderedListUnaffected() {
        let editor = makeEditor()
        editor.loadContent("- a\n- b\n- c\n")
        let range = (editor.rawSource as NSString).range(of: "- b\n")
        editor.setSelectedRange(range)
        editor.insertText("", replacementRange: range)
        #expect(editor.rawSource == "- a\n- c\n")
    }

    @Test("An untouched item inside the renumbered span keeps its dimmed marker")
    @MainActor func untouchedItemInSpanStaysDimmed() {
        // "1. a" sits in the same contiguous run as the renumbered items but
        // is never itself rewritten and never the active block after the
        // edit — `recomposeReplacing` wipes its WHOLE oldRange to base
        // attributes before restyling only the dirty set, so every block in
        // that span (not just the ones whose digits changed) must be marked
        // dirty or this one is left showing an unstyled (undimmed) marker.
        let editor = makeEditor()
        editor.loadContent("1. a\n2. b\n3. c\n4. d\n5. e\n")
        let range = (editor.rawSource as NSString).range(of: "2. b\n")
        editor.setSelectedRange(range)
        editor.insertText("", replacementRange: range)
        #expect(editor.rawSource == "1. a\n2. c\n3. d\n4. e\n")

        // The caret (and thus the active, intentionally-undimmed block) sits
        // at the deletion point, on "2. c" — "1. a" stays inactive throughout.
        #expect(editor.blocks[0].content == "1. a")
        #expect(fgColor(at: editor.blocks[0].range.location, in: editor) == NSColor.tertiaryLabelColor)
    }

    @Test("Splitting one list into two at the same depth renumbers both halves")
    @MainActor func splittingIntoTwoRunsRenumbersBoth() {
        // Enter on an already-empty list item removes its marker
        // (EditorTextView+ListContinuation.swift's root-level-empty branch),
        // leaving a blank line that splits one depth-0 run into two disjoint
        // ones. Both must still get renumbered independently — a naive
        // "one depth, one run" dedup would fix the first (trivially, since
        // "1." alone is already correct) and silently skip the second.
        let editor = makeEditor()
        editor.loadContent("1. a\n2. \n4. b\n4. c")
        // Caret at the end of the empty "2. " item.
        let caret = (editor.rawSource as NSString).range(of: "2. ").upperBound
        editor.setSelectedRange(NSRange(location: caret, length: 0))
        editor.insertNewline(nil)
        #expect(editor.rawSource == "1. a\n\n4. b\n5. c")
    }

    @Test("Indenting a list item renumbers both the old and new level")
    @MainActor func indentRenumbersBothLevels() {
        let editor = makeEditor()
        editor.loadContent("1. a\n2. b\n  1. x\n  2. y\n3. c")
        // Tab-indent "2. b" into the nested (depth-1) run: the old top-level
        // run loses a member (c should renumber 3→2), and the nested run
        // gains a new head (x, y should renumber to 3, 4 after b's "2.").
        let caret = (editor.rawSource as NSString).range(of: "2. b").location
        editor.setSelectedRange(NSRange(location: caret, length: 0))
        editor.insertTab(nil)
        #expect(editor.rawSource == "1. a\n  2. b\n  3. x\n  4. y\n2. c")
    }

    @Test("Dedenting a list item renumbers both the old and new level")
    @MainActor func dedentRenumbersBothLevels() {
        let editor = makeEditor()
        editor.loadContent("1. a\n  1. x\n  2. y\n2. b\n3. c")
        // Shift-Tab-dedent "2. y": it stays in place (dedent only strips
        // indent, it doesn't move lines), so it now sits at depth 0 between
        // "a" and "b" in document order. The nested run loses its second
        // member (x alone stays "1."), and the top-level run gains a new
        // member right after "a", pushing b/c's numbers up by one.
        let caret = (editor.rawSource as NSString).range(of: "2. y").location
        editor.setSelectedRange(NSRange(location: caret, length: 0))
        editor.insertBacktab(nil)
        #expect(editor.rawSource == "1. a\n  1. x\n2. y\n3. b\n4. c")
    }

    @Test("Undo restores the pre-renumber text in a single step")
    @MainActor func undoRestoresOriginalInOneStep() {
        let editor = makeEditor()
        editor.loadContent("1. a\n2. b\n3. c")
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        editor.insertNewline(nil)
        #expect(editor.rawSource == "1. a\n2. \n3. b\n4. c")

        editor.undo(nil)
        #expect(editor.rawSource == "1. a\n2. b\n3. c")

        editor.redo(nil)
        #expect(editor.rawSource == "1. a\n2. \n3. b\n4. c")
    }
}
