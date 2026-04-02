import AppKit

// MARK: - Active Block Syntax Highlighting & Inactive Block Rendering

extension EditorTextView {

    /// Color for dimmed syntax delimiters (*, **, `, #, etc.)
    var syntaxDimColor: NSColor { .tertiaryLabelColor }

    /// Builds an NSAttributedString of the raw markdown with syntax highlighting.
    ///
    /// Uses `swift-markdown` (cmark-gfm) to parse the source, then maps the
    /// AST's source ranges back onto the raw text: bold/italic font traits on
    /// content, dimmed color on delimiters.  Because the same parser powers
    /// `AttributedString(markdown:)`, the active block's highlighting is
    /// consistent with rendered (non-active) blocks — including edge cases
    /// like mismatched delimiters (`**hi*`).
    func highlightSyntax(_ markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: markdown, attributes: baseAttributes)
        let spans = SyntaxHighlighter.parse(markdown)

        for span in spans {
            // Dim delimiter characters
            for dr in span.delimiterRanges {
                guard dr.upperBound <= result.length else { continue }
                result.addAttribute(.foregroundColor, value: syntaxDimColor, range: dr)
            }

            switch span.kind {
            case .bold:
                guard span.contentRange.upperBound <= result.length else { continue }
                let bold = NSFontManager.shared.convert(bodyFont, toHaveTrait: .boldFontMask)
                result.addAttribute(.font, value: bold, range: span.contentRange)

            case .italic:
                guard span.contentRange.upperBound <= result.length else { continue }
                let italic = NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask)
                result.addAttribute(.font, value: italic, range: span.contentRange)

            case .boldItalic:
                guard span.contentRange.upperBound <= result.length else { continue }
                let bi = NSFontManager.shared.convert(bodyFont, toHaveTrait: [.boldFontMask, .italicFontMask])
                result.addAttribute(.font, value: bi, range: span.contentRange)

            case .code:
                break

            case .heading(let level):
                guard span.fullRange.upperBound <= result.length else { continue }
                let scale: CGFloat = level == 1 ? 1.5 : level == 2 ? 1.3 : level == 3 ? 1.15 : 1.0
                let sized = NSFont(descriptor: bodyFont.fontDescriptor,
                                   size: bodyFont.pointSize * scale) ?? bodyFont
                let heading = NSFontManager.shared.convert(sized, toHaveTrait: .boldFontMask)
                result.addAttribute(.font, value: heading, range: span.fullRange)
                // Re-dim delimiters (they got heading font above)
                for dr in span.delimiterRanges {
                    guard dr.upperBound <= result.length else { continue }
                    result.addAttribute(.foregroundColor, value: syntaxDimColor, range: dr)
                }
            }
        }

        return result
    }

    /// Re-applies syntax highlighting to the active block in the text storage.
    /// Called after each keystroke to keep formatting in sync with content.
    func applySyntaxHighlighting() {
        guard let ts = textStorage,
              let activeIdx = activeBlockIndex,
              activeIdx < displayRanges.count,
              activeIdx < blocks.count else { return }

        let displayRange = displayRanges[activeIdx]
        guard displayRange.upperBound <= ts.length else { return }

        let content = blocks[activeIdx].content
        let highlighted = highlightSyntax(content)
        let offset = displayRange.location

        isUpdating = true
        ts.beginEditing()

        highlighted.enumerateAttributes(in: NSRange(location: 0, length: highlighted.length), options: []) { attrs, range, _ in
            let displayR = NSRange(location: range.location + offset, length: range.length)
            ts.setAttributes(attrs, range: displayR)
        }

        ts.endEditing()
        isUpdating = false

        typingAttributes = baseAttributes
    }

    // MARK: - Inactive Block Rendering

    /// Computes the exact delimiter ranges to strip for a rendered (inactive) block.
    ///
    /// Unlike `span.delimiterRanges` (which uses cmark's full source range and may
    /// include literal characters in mismatched cases like `**hi*`), this computes
    /// delimiters from the known width per span kind, anchored on `contentRange`.
    private func renderDelimiters(for span: SyntaxHighlighter.Span) -> [NSRange] {
        switch span.kind {
        case .italic:
            return [
                NSRange(location: span.contentRange.location - 1, length: 1),
                NSRange(location: span.contentRange.upperBound, length: 1),
            ]
        case .bold:
            return [
                NSRange(location: span.contentRange.location - 2, length: 2),
                NSRange(location: span.contentRange.upperBound, length: 2),
            ]
        case .boldItalic:
            return [
                NSRange(location: span.contentRange.location - 3, length: 3),
                NSRange(location: span.contentRange.upperBound, length: 3),
            ]
        case .code:
            return span.delimiterRanges
        case .heading:
            return span.delimiterRanges
        }
    }

    func renderMarkdown(_ markdown: String) -> NSAttributedString {
        let spans = SyntaxHighlighter.parse(markdown)

        // Compute exact delimiter ranges for each span, sorted descending for back-to-front removal
        var allDelimRanges: [NSRange] = []
        for span in spans {
            allDelimRanges.append(contentsOf: renderDelimiters(for: span))
        }
        allDelimRanges.sort { $0.location > $1.location }

        // Build stripped text by removing delimiters
        var stripped = markdown
        var removals: [(location: Int, length: Int)] = []
        for dr in allDelimRanges {
            guard dr.location >= 0, dr.upperBound <= (stripped as NSString).length else { continue }
            let startUTF16 = stripped.utf16.index(stripped.utf16.startIndex, offsetBy: dr.location)
            let endUTF16 = stripped.utf16.index(startUTF16, offsetBy: dr.length)
            stripped.removeSubrange(startUTF16..<endUTF16)
            removals.append((location: dr.location, length: dr.length))
        }
        // Reverse so they're in ascending order for offset mapping
        removals.reverse()

        func mappedOffset(_ original: Int) -> Int {
            var shift = 0
            for r in removals {
                if original > r.location {
                    shift += r.length
                }
            }
            return original - shift
        }

        let result = NSMutableAttributedString(string: stripped, attributes: baseAttributes)

        for span in spans {
            let start = mappedOffset(span.contentRange.location)
            let end = mappedOffset(span.contentRange.upperBound)
            let mappedRange = NSRange(location: start, length: max(0, end - start))
            guard mappedRange.upperBound <= result.length else { continue }

            switch span.kind {
            case .bold:
                let bold = NSFontManager.shared.convert(bodyFont, toHaveTrait: .boldFontMask)
                result.addAttribute(.font, value: bold, range: mappedRange)
            case .italic:
                let italic = NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask)
                result.addAttribute(.font, value: italic, range: mappedRange)
            case .boldItalic:
                let bi = NSFontManager.shared.convert(bodyFont, toHaveTrait: [.boldFontMask, .italicFontMask])
                result.addAttribute(.font, value: bi, range: mappedRange)
            case .code:
                break
            case .heading(let level):
                let fullStart = mappedOffset(span.fullRange.location)
                let fullEnd = mappedOffset(span.fullRange.upperBound)
                let mappedFull = NSRange(location: fullStart, length: max(0, fullEnd - fullStart))
                guard mappedFull.upperBound <= result.length else { continue }
                let scale: CGFloat = level == 1 ? 1.5 : level == 2 ? 1.3 : level == 3 ? 1.15 : 1.0
                let sized = NSFont(descriptor: bodyFont.fontDescriptor,
                                   size: bodyFont.pointSize * scale) ?? bodyFont
                let heading = NSFontManager.shared.convert(sized, toHaveTrait: .boldFontMask)
                result.addAttribute(.font, value: heading, range: mappedFull)
            }
        }

        return result
    }
}
