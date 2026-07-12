import AppKit

// MARK: - Ordered List Renumbering
//
// Keeps a contiguous run of ordered ("1. ", "1) ") list items sequential
// after an edit changes its item count (insert mid-list, delete an item,
// paste). Scoped to the nesting depth the edit touched — sibling depths and
// unrelated lists elsewhere in the document are never rewritten. Called once
// per edit from `syncRawSourceFromDisplay` (EditorTextView+EditFlow.swift),
// after `blocks` has been reparsed to the post-edit state.

extension EditorTextView {

    private static let orderedMarkerRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)(\d+)([.)])[ ]"#
    )

    /// Leading indent, number, delimiter, and the digits' block-local NSRange
    /// when `content` is an ordered list item line; nil otherwise.
    private func orderedMarker(_ content: String) -> (indent: String, number: Int, digits: NSRange, delim: Character)? {
        let ns = content as NSString
        guard let m = Self.orderedMarkerRegex.firstMatch(in: content, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        let indent = ns.substring(with: m.range(at: 1))
        guard let number = Int(ns.substring(with: m.range(at: 2))) else { return nil }
        let delim = ns.substring(with: m.range(at: 3)).first ?? "."
        return (indent, number, m.range(at: 2), delim)
    }

    /// Reuses the render-time indent→depth mapping so renumbering agrees with
    /// what's actually drawn.
    private func depthOf(_ block: Block) -> Int {
        let indent = block.content.prefix(while: { $0 == " " || $0 == "\t" })
        return listDepth(leadingWhitespace: String(indent))
    }

    /// Entry point: renumbers every distinct contiguous ordered run touched
    /// by the edit — including two disjoint runs at the same depth (e.g. an
    /// edit that splits one list into two, or an indent/dedent that moves
    /// items between an old list and a new/existing one at a different
    /// depth). `touchedBlocks`' block count is assumed unchanged by any
    /// rewrite this makes (only digit widths inside existing lines change),
    /// so indices computed up front stay valid across the whole call.
    func renumberOrderedListRunsIfNeeded(touching touchedBlocks: Range<Int>) {
        guard !blocks.isEmpty else { return }
        let lo = max(0, touchedBlocks.lowerBound - 1)
        let hi = min(blocks.count, touchedBlocks.upperBound + 1)
        guard lo < hi else { return }

        var processed = IndexSet()
        for idx in lo..<hi {
            guard !processed.contains(idx),
                  blocks[idx].kind == .listItem,
                  orderedMarker(blocks[idx].content) != nil else { continue }
            let depth = depthOf(blocks[idx])
            let bounds = orderedRunBounds(seedIndex: idx, depth: depth)
            // Only the same-depth members actually belong to this run's
            // numbering — `bounds` also spans deeper nested children purely
            // as pass-through text, and marking those processed here would
            // wrongly suppress their own, separate depth's renumbering pass
            // later in this loop.
            let sequence = bounds.filter { depthOf(blocks[$0]) == depth }
            for seqIdx in sequence { processed.insert(seqIdx) }
            renumberOrderedListRun(bounds: bounds, sequence: sequence)
        }
    }

    /// Walks outward from `seedIndex` to the bounds of the contiguous
    /// same-depth ordered run: stops (exclusive) at a blank line, a
    /// non-listItem block, a shallower list item, or a same-depth list item
    /// that isn't ordered (a marker-type change starts a new list). A
    /// deeper list item is included in the span but not the numbering.
    private func orderedRunBounds(seedIndex: Int, depth: Int) -> ClosedRange<Int> {
        func continues(_ idx: Int) -> Bool {
            guard blocks[idx].kind == .listItem else { return false }
            let d = depthOf(blocks[idx])
            if d < depth { return false }
            if d == depth { return orderedMarker(blocks[idx].content) != nil }
            return true // deeper: nested child, part of the span
        }
        var lo = seedIndex
        while lo > 0, continues(lo - 1) { lo -= 1 }
        var hi = seedIndex
        while hi < blocks.count - 1, continues(hi + 1) { hi += 1 }
        return lo...hi
    }

    /// Renumbers the contiguous ordered run spanning `bounds`; `sequence` —
    /// precomputed by the caller — is the same-depth subset of `bounds` that
    /// actually gets numbered. Preserves the run's starting number. No-op
    /// (no storage mutation) when the run is already sequential.
    private func renumberOrderedListRun(bounds: ClosedRange<Int>, sequence: [Int]) {
        guard let first = sequence.first,
              let start = orderedMarker(blocks[first].content)?.number else { return }

        var rewrites: [(idx: Int, digits: NSRange, newNumber: String)] = []
        for (i, idx) in sequence.enumerated() {
            guard let marker = orderedMarker(blocks[idx].content) else { continue }
            let expected = start + i
            if marker.number != expected {
                rewrites.append((idx, marker.digits, String(expected)))
            }
        }
        guard !rewrites.isEmpty else { return }

        let oldSpan = NSRange(
            location: blocks[bounds.lowerBound].range.location,
            length: blocks[bounds.upperBound].range.upperBound - blocks[bounds.lowerBound].range.location)

        let rewriteByIndex = Dictionary(uniqueKeysWithValues: rewrites.map { ($0.idx, $0) })
        var netDelta = 0
        let newText = bounds.map { idx -> String in
            guard let r = rewriteByIndex[idx] else { return blocks[idx].content }
            let content = blocks[idx].content as NSString
            let newLine = content.replacingCharacters(in: r.digits, with: r.newNumber)
            return newLine
        }.joined(separator: "\n")

        let caretBefore = selectedRange().location
        for idx in bounds {
            guard let r = rewriteByIndex[idx] else { continue }
            let digitsStart = blocks[idx].range.location + r.digits.location
            if digitsStart < caretBefore {
                netDelta += (r.newNumber as NSString).length - r.digits.length
            }
        }
        let caretAfter = max(0, caretBefore + netDelta)

        rawSource = (rawSource as NSString).replacingCharacters(in: oldSpan, with: newText)
        blocks = BlockParser.parse(rawSource, previous: blocks)

        // `recomposeReplacing` wipes the whole replaced span to base
        // attributes before restyling only the dirty blocks — every block in
        // `bounds` sits inside that span, not just the ones whose digits
        // changed, so all of them must be marked dirty or the untouched ones
        // are left showing unstyled (undimmed) markers.
        let dirty = IndexSet(bounds)
        recomposeReplacing(oldRange: oldSpan, with: newText, dirty: dirty, cursorInRaw: caretAfter)
    }
}
