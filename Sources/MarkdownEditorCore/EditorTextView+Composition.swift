import AppKit

// MARK: - Display Composition & Coordinate Mapping

extension EditorTextView {

    // MARK: - Display Composition (full recompose)
    //
    // Called when the active block changes.  Replaces the entire text storage.

    func recompose(cursorInRaw: Int, selectionInRaw: NSRange? = nil) {
        isUpdating = true

        activeBlockIndex = blockIndexForRawOffset(cursorInRaw)

        let composed = NSMutableAttributedString()
        displayRanges = []

        for (i, block) in blocks.enumerated() {
            if i > 0 {
                composed.append(NSAttributedString(string: blockSeparator, attributes: baseAttributes))
            }

            let blockDisplayStart = composed.length

            if i == activeBlockIndex {
                composed.append(highlightSyntax(block.content))
            } else {
                composed.append(renderMarkdown(block.content))
            }

            let blockDisplayLength = composed.length - blockDisplayStart
            displayRanges.append(NSRange(location: blockDisplayStart, length: blockDisplayLength))
        }

        let fullRange = NSRange(location: 0, length: textStorage!.length)
        textStorage?.beginEditing()
        textStorage?.replaceCharacters(in: fullRange, with: composed)
        textStorage?.endEditing()

        if let rawSel = selectionInRaw, rawSel.length > 0 {
            let displayStart = rawOffsetToDisplayOffset(rawSel.location)
            let displayEnd = rawOffsetToDisplayOffset(rawSel.location + rawSel.length)
            let len = textStorage!.length
            let displaySel = NSRange(
                location: min(displayStart, len),
                length: max(0, min(displayEnd, len) - min(displayStart, len))
            )
            setSelectedRange(displaySel)
        } else {
            let displayCursor = rawOffsetToDisplayOffset(cursorInRaw)
            let clamped = min(displayCursor, textStorage!.length)
            setSelectedRange(NSRange(location: clamped, length: 0))
        }

        typingAttributes = baseAttributes

        isUpdating = false
    }

    /// Recalculates displayRanges from current blocks without touching textStorage.
    func recalcDisplayRanges() {
        displayRanges = []
        var offset = 0
        for (i, block) in blocks.enumerated() {
            if i > 0 {
                offset += separatorLength
            }
            let displayLen: Int
            if i == activeBlockIndex {
                displayLen = (block.content as NSString).length
            } else {
                let rendered = renderMarkdown(block.content)
                displayLen = rendered.length
            }
            displayRanges.append(NSRange(location: offset, length: displayLen))
            offset += displayLen
        }
    }

    // MARK: - Coordinate Mapping

    func blockIndexForRawOffset(_ rawOffset: Int) -> Int? {
        for (i, block) in blocks.enumerated() {
            if rawOffset >= block.range.location && rawOffset <= block.range.upperBound {
                return i
            }
        }
        return blocks.isEmpty ? nil : blocks.count - 1
    }

    func displayOffsetToRawOffset(_ displayOffset: Int) -> Int {
        for (i, displayRange) in displayRanges.enumerated() {
            guard i < blocks.count else { break }
            let block = blocks[i]

            if displayOffset <= displayRange.upperBound {
                let offsetInBlock = max(0, displayOffset - displayRange.location)

                if i == activeBlockIndex {
                    let clampedOffset = min(offsetInBlock, (block.content as NSString).length)
                    return block.range.location + clampedOffset
                } else {
                    let displayLen = displayRange.length
                    let rawLen = (block.content as NSString).length
                    if displayLen > 0 {
                        let proportion = Double(offsetInBlock) / Double(displayLen)
                        let mapped = Int(proportion * Double(rawLen))
                        return block.range.location + min(mapped, rawLen)
                    }
                    return block.range.location
                }
            }

            let separatorEnd = (i + 1 < displayRanges.count)
                ? displayRanges[i + 1].location
                : (textStorage?.length ?? displayRange.upperBound)
            if displayOffset < separatorEnd {
                let sepOffset = displayOffset - displayRange.upperBound
                return block.range.upperBound + sepOffset
            }
        }

        return (rawSource as NSString).length
    }

    func rawOffsetToDisplayOffset(_ rawOffset: Int) -> Int {
        for (i, block) in blocks.enumerated() {
            guard i < displayRanges.count else { break }
            let displayRange = displayRanges[i]

            if rawOffset <= block.range.upperBound {
                let offsetInBlock = max(0, rawOffset - block.range.location)

                if i == activeBlockIndex {
                    return displayRange.location + min(offsetInBlock, displayRange.length)
                } else {
                    let rawLen = (block.content as NSString).length
                    if rawLen > 0 {
                        let proportion = Double(offsetInBlock) / Double(rawLen)
                        let mapped = Int(proportion * Double(displayRange.length))
                        return displayRange.location + min(mapped, displayRange.length)
                    }
                    return displayRange.location
                }
            }

            let nextRawStart = (i + 1 < blocks.count)
                ? blocks[i + 1].range.location
                : (rawSource as NSString).length
            if rawOffset < nextRawStart {
                let sepOffset = rawOffset - block.range.upperBound
                return displayRange.upperBound + sepOffset
            }
        }

        return textStorage?.length ?? 0
    }

    func displayRangeToRawRange(_ displayRange: NSRange) -> NSRange {
        let rawStart = displayOffsetToRawOffset(displayRange.location)
        let rawEnd = displayOffsetToRawOffset(displayRange.location + displayRange.length)
        return NSRange(location: rawStart, length: max(0, rawEnd - rawStart))
    }
}
