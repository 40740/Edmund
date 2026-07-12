import Testing
import Foundation
import AppKit
@testable import EdmundCore

// A table cell wider than its (clamped) column can't be kern-aligned in
// place — TextKit 2 only wraps a whole paragraph at the container edge, and
// NSTextTable/NSTextBlock are banned (they revert the view to TextKit 1). The
// fix hides that cell's real characters and records a `.tableCellWraps`
// attribute the layout fragment redraws wrapped. See EditorTextView+TextKit2.swift.

@Suite("Table cell wrapping")
@MainActor
struct TableWrapRenderingTests {

    private func lastRowStart(_ styled: NSAttributedString) -> Int {
        let s = styled.string as NSString
        let nl = s.range(of: "\n", options: .backwards)
        return nl.location == NSNotFound ? 0 : nl.location + 1
    }

    private func cellWraps(at offset: Int, in styled: NSAttributedString) -> [TableCellWrap] {
        guard offset < styled.length else { return [] }
        let list = styled.attribute(.tableCellWraps, at: offset, effectiveRange: nil) as? TableCellWrapList
        return list?.wraps ?? []
    }

    @Test("Cells that fit their column carry no wrap attribute")
    func fittingCellsUnaffected() {
        let editor = makeEditor()
        let styled = editor.styleBlock("| a | b |\n|---|---|\n| x | y |", cursorPosition: nil)
        let start = lastRowStart(styled)
        #expect(cellWraps(at: start, in: styled).isEmpty)
        // Existing kern-based alignment still runs for the fitting cell.
        #expect(styled.attribute(.tableCellWraps, at: 0, effectiveRange: nil) == nil)
    }

    @Test("A cell wider than its column gets a wrap marker sized to overflow")
    func overflowingCellGetsWrapMarker() {
        let editor = makeEditor()
        let longText = Array(repeating: "overflow", count: 30).joined(separator: " ")
        let source = "| short | wide |\n|---|---|\n| x | \(longText) |"
        let styled = editor.styleBlock(source, cursorPosition: nil)
        let start = lastRowStart(styled)

        let wraps = cellWraps(at: start, in: styled)
        #expect(wraps.count == 1)
        guard let wrap = wraps.first else { return }
        // The cell's natural width must genuinely exceed the column it was
        // clamped to — otherwise it wouldn't need to wrap at all.
        #expect(wrap.styled.size().width > wrap.contentWidth)
        #expect(wrap.contentWidth > 0)
    }

    @Test("Table storage stays byte-for-byte unchanged when a cell wraps")
    func storageUnchangedByWrapping() {
        let editor = makeEditor()
        let longText = Array(repeating: "overflow", count: 30).joined(separator: " ")
        let source = "| short | wide |\n|---|---|\n| x | \(longText) |"
        let styled = editor.styleBlock(source, cursorPosition: nil)
        #expect(styled.string == source)
    }

    @Test("Every row shares the same column border offsets even with a wrapping row")
    func columnOffsetsConsistentAcrossRows() {
        let editor = makeEditor()
        let longText = Array(repeating: "overflow", count: 30).joined(separator: " ")
        let source = "| short | wide |\n|---|---|\n| x | \(longText) |\n| a | b |"
        let styled = editor.styleBlock(source, cursorPosition: nil)

        var offsetsPerRow: [[CGFloat]] = []
        let s = styled.string as NSString
        var lineStart = 0
        while lineStart <= s.length {
            if case .tableRow(let offsets, _, _, _)? =
                blockDecoration(at: lineStart, in: styled)?.kind {
                offsetsPerRow.append(offsets)
            }
            let nl = s.range(of: "\n", range: NSRange(location: lineStart, length: s.length - lineStart))
            guard nl.location != NSNotFound else { break }
            lineStart = nl.upperBound
        }
        #expect(offsetsPerRow.count >= 2)
        #expect(offsetsPerRow.dropFirst().allSatisfy { $0 == offsetsPerRow[0] })
    }

    @Test("distributeColumnWidths keeps under-fair-share columns, clamps the rest")
    func distributeColumnWidthsClamps() {
        let result = distributeColumnWidths(natural: [20, 200], available: 100, minWidth: 10)
        #expect(result[0] == 20)
        #expect(result[1] < 200)
        #expect(result[1] >= 10)
    }

    @Test("distributeColumnWidths returns natural widths when everything fits")
    func distributeColumnWidthsNoOp() {
        let result = distributeColumnWidths(natural: [20, 30], available: 1000, minWidth: 10)
        #expect(result == [20, 30])
    }
}
