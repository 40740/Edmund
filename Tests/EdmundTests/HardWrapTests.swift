import Testing
@testable import EdmundCore

// Hard wrap / unwrap (Edit ▸ Document ▸ "Automatically hard-wrap long lines").
// Pure String → String, so no editor or window is involved.

@Suite("HardWrap")
struct HardWrapTests {

    /// Five words of ten characters each — 10, 21, 32 … so the break points are
    /// easy to reason about against the 80-column limit.
    private func words(_ n: Int) -> String {
        (1...n).map { String(repeating: "w", count: 9) + String($0 % 10) }
            .joined(separator: " ")
    }

    // MARK: - Wrap

    @Test("Wraps at the last space before column 80")
    func breaksAtColumn() {
        // 8 words × 10 chars + 7 spaces = 87 > 80; 7 words = 76 fits.
        let lines = HardWrap.wrap(words(8)).components(separatedBy: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].count == 76)
        #expect(lines.allSatisfy { !$0.hasSuffix(" ") })
    }

    @Test("A short paragraph is left alone")
    func shortParagraphUnchanged() {
        #expect(HardWrap.wrap("one two three") == "one two three")
    }

    @Test("A word longer than the column stays intact on its own line")
    func neverBreaksMidWord() {
        let giant = String(repeating: "x", count: 100)
        let wrapped = HardWrap.wrap("short \(giant) tail")
        #expect(wrapped.contains(giant))
        #expect(wrapped.components(separatedBy: "\n").contains(giant))
    }

    @Test("A break never puts a list marker at the start of a line")
    func neverCreatesListSyntax() {
        // "1." would land at column 0 on a naive greedy fill.
        let text = words(7) + " 1. 50 per unit"
        for line in HardWrap.wrap(text).components(separatedBy: "\n") {
            #expect(!line.hasPrefix("1."))
        }
    }

    @Test("A break never puts a heading, quote, dash or fence at line start")
    func neverCreatesOtherSyntax() {
        for token in ["#", "##", ">", "-", "*", "---", "===", "|", "```", "~~~"] {
            let wrapped = HardWrap.wrap(words(7) + " \(token) tail text here")
            for line in wrapped.components(separatedBy: "\n") {
                #expect(!line.hasPrefix(token), "\(token) reached line start")
            }
        }
    }

    @Test("A dash inside a word is not mistaken for a list marker")
    func hyphenatedWordStillBreaks() {
        let wrapped = HardWrap.wrap(words(7) + " -dash tail")
        // "-dash" is not a marker, so the fill is free to break in front of it.
        #expect(wrapped.contains("\n-dash"))
    }

    @Test("Paragraph indent is preserved on continuation lines")
    func preservesIndent() {
        let lines = HardWrap.wrap("  " + words(8)).components(separatedBy: "\n")
        #expect(lines.count == 2)
        #expect(lines.allSatisfy { $0.hasPrefix("  ") })
    }

    // MARK: - Unwrap

    @Test("A wrapped paragraph becomes one line")
    func joinsParagraph() {
        #expect(HardWrap.unwrap("one two\nthree four") == "one two three four")
    }

    @Test("Blank lines still separate paragraphs")
    func keepsParagraphBreaks() {
        #expect(HardWrap.unwrap("one\ntwo\n\nthree\nfour") == "one two\n\nthree four")
    }

    @Test("A two-space hard break survives the join")
    func keepsTwoSpaceHardBreak() {
        #expect(HardWrap.unwrap("one  \ntwo three") == "one  \ntwo three")
    }

    @Test("A trailing-backslash hard break survives the join")
    func keepsBackslashHardBreak() {
        #expect(HardWrap.unwrap("one\\\ntwo") == "one\\\ntwo")
    }

    @Test("An escaped backslash is not a hard break")
    func escapedBackslashJoins() {
        #expect(HardWrap.unwrap("one\\\\\ntwo") == "one\\\\ two")
    }

    @Test("A single trailing space does not double up in the join")
    func trimsInsignificantTrailingSpace() {
        #expect(HardWrap.unwrap("one \ntwo") == "one two")
    }

    @Test("Continuation-line indent is dropped when joining")
    func dropsContinuationIndent() {
        #expect(HardWrap.unwrap("  one\n  two") == "  one two")
    }

    @Test("A hard break survives a wrap too")
    func wrapKeepsHardBreak() {
        let wrapped = HardWrap.wrap("one  \ntwo")
        #expect(wrapped == "one  \ntwo")
    }

    // MARK: - Blocks that must never be touched

    /// Every kind the transform is supposed to copy through verbatim, each with
    /// a line long enough that a careless wrap would show up immediately.
    private var immuneDocument: String {
        let long = words(12)
        return """
        ---
        title: \(long)
        ---

        # \(long)

        ```swift
        let x = "\(long)"
        ```

            indented code \(long)

        | a | b |
        | --- | --- |
        | \(long) | y |

        > quoted \(long)

        - list item \(long)

        $$
        \(long)
        $$

        <div>\(long)</div>

        ***
        """
    }

    @Test("Fences, tables, headings, front matter, lists and quotes are copied through")
    func blocksAreImmune() {
        #expect(HardWrap.wrap(immuneDocument) == immuneDocument)
        #expect(HardWrap.unwrap(immuneDocument) == immuneDocument)
    }

    // MARK: - Round trips

    @Test("Wrapping an already-wrapped document changes nothing")
    func wrapIsIdempotent() {
        let once = HardWrap.wrap(words(30))
        #expect(HardWrap.wrap(once) == once)
    }

    @Test("Unwrapping an already-joined document changes nothing")
    func unwrapIsIdempotent() {
        let once = HardWrap.unwrap(words(30))
        #expect(HardWrap.unwrap(once) == once)
    }

    @Test("A document wrapped at 80 round-trips through unwrap and back")
    func roundTrip() {
        let wrapped = HardWrap.wrap("\(words(30))\n\n# Heading\n\n\(words(17))")
        #expect(HardWrap.wrap(HardWrap.unwrap(wrapped)) == wrapped)
    }

    @Test("Empty input is handled")
    func empty() {
        #expect(HardWrap.wrap("") == "")
        #expect(HardWrap.unwrap("") == "")
    }
}
