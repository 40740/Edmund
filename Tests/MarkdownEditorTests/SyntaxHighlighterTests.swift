import Testing
import Foundation
@testable import MarkdownEditorCore

// MARK: - Bold

@Suite("SyntaxHighlighter — Bold")
struct BoldTests {

    @Test("**bold** produces a bold span")
    func doubleStar() {
        let spans = SyntaxHighlighter.parse("**bold**")
        #expect(spans.count == 1)
        let s = spans[0]
        #expect(s.kind == .bold)
        #expect(s.fullRange == NSRange(location: 0, length: 8))
        #expect(s.contentRange == NSRange(location: 2, length: 4))
        #expect(s.delimiterRanges.count == 2)
        #expect(s.delimiterRanges[0] == NSRange(location: 0, length: 2))
        #expect(s.delimiterRanges[1] == NSRange(location: 6, length: 2))
    }

    @Test("__bold__ with underscores")
    func doubleUnderscore() {
        let spans = SyntaxHighlighter.parse("__bold__")
        #expect(spans.count == 1)
        #expect(spans[0].kind == .bold)
        #expect(spans[0].contentRange == NSRange(location: 2, length: 4))
    }

    @Test("text **bold** text has correct offset")
    func boldInMiddle() {
        let spans = SyntaxHighlighter.parse("hello **world** end")
        #expect(spans.count == 1)
        #expect(spans[0].kind == .bold)
        #expect(spans[0].fullRange == NSRange(location: 6, length: 9))
        #expect(spans[0].contentRange == NSRange(location: 8, length: 5))
    }
}

// MARK: - Italic

@Suite("SyntaxHighlighter — Italic")
struct ItalicTests {

    @Test("*italic* produces an italic span")
    func singleStar() {
        let spans = SyntaxHighlighter.parse("*italic*")
        #expect(spans.count == 1)
        let s = spans[0]
        #expect(s.kind == .italic)
        #expect(s.fullRange == NSRange(location: 0, length: 8))
        #expect(s.contentRange == NSRange(location: 1, length: 6))
    }

    @Test("_italic_ with underscore")
    func singleUnderscore() {
        let spans = SyntaxHighlighter.parse("_italic_")
        #expect(spans.count == 1)
        #expect(spans[0].kind == .italic)
    }
}

// MARK: - Bold + Italic

@Suite("SyntaxHighlighter — Bold+Italic")
struct BoldItalicTests {

    @Test("***text*** produces boldItalic")
    func tripleStar() {
        let spans = SyntaxHighlighter.parse("***both***")
        #expect(spans.count == 1)
        let s = spans[0]
        #expect(s.kind == .boldItalic)
        #expect(s.contentRange == NSRange(location: 3, length: 4))
        #expect(s.delimiterRanges[0] == NSRange(location: 0, length: 3))
        #expect(s.delimiterRanges[1] == NSRange(location: 7, length: 3))
    }

    @Test("___text___ with underscores")
    func tripleUnderscore() {
        let spans = SyntaxHighlighter.parse("___both___")
        #expect(spans.count == 1)
        #expect(spans[0].kind == .boldItalic)
    }
}

// MARK: - Code

@Suite("SyntaxHighlighter — Code")
struct CodeTests {

    @Test("`code` produces a code span")
    func inlineCode() {
        let spans = SyntaxHighlighter.parse("`code`")
        #expect(spans.count == 1)
        let s = spans[0]
        #expect(s.kind == .code)
        #expect(s.contentRange == NSRange(location: 1, length: 4))
        #expect(s.delimiterRanges[0] == NSRange(location: 0, length: 1))
        #expect(s.delimiterRanges[1] == NSRange(location: 5, length: 1))
    }

    @Test("Code spans suppress inner parsing")
    func codeOpaqueToMarkdown() {
        let spans = SyntaxHighlighter.parse("`**not bold**`")
        #expect(spans.count == 1)
        #expect(spans[0].kind == .code)
    }
}

// MARK: - Headings

@Suite("SyntaxHighlighter — Headings")
struct HeadingTests {

    @Test("# Heading produces level-1 heading")
    func h1() {
        let spans = SyntaxHighlighter.parse("# Hello")
        #expect(spans.count == 1)
        let s = spans[0]
        #expect(s.kind == .heading(1))
        #expect(s.contentRange == NSRange(location: 2, length: 5))
        #expect(s.delimiterRanges[0] == NSRange(location: 0, length: 2))
    }

    @Test("## Heading produces level-2")
    func h2() {
        let spans = SyntaxHighlighter.parse("## Sub")
        #expect(spans.count == 1)
        #expect(spans[0].kind == .heading(2))
    }

    @Test("### Heading produces level-3")
    func h3() {
        let spans = SyntaxHighlighter.parse("### Sub sub")
        #expect(spans.count == 1)
        #expect(spans[0].kind == .heading(3))
    }

    @Test("###### deepest heading is level 6")
    func h6() {
        let spans = SyntaxHighlighter.parse("###### Deep")
        #expect(spans.count == 1)
        #expect(spans[0].kind == .heading(6))
    }

    @Test("# without space is not a heading")
    func noSpace() {
        let spans = SyntaxHighlighter.parse("#notaheading")
        #expect(spans.isEmpty)
    }

    @Test("Heading suppresses inline parsing in its range")
    func headingSuppressesInline() {
        let spans = SyntaxHighlighter.parse("# **Bold heading**")
        #expect(spans.count == 1)
        #expect(spans[0].kind == .heading(1))
    }
}

// MARK: - Priority & Overlap

@Suite("SyntaxHighlighter — Priority")
struct PriorityTests {

    @Test("*** is matched as boldItalic, not bold + italic")
    func tripleStarPriority() {
        let spans = SyntaxHighlighter.parse("***text***")
        #expect(spans.count == 1)
        #expect(spans[0].kind == .boldItalic)
    }

    @Test("Multiple spans in one line")
    func multipleSpans() {
        let spans = SyntaxHighlighter.parse("**bold** and *italic*")
        #expect(spans.count == 2)
        #expect(spans[0].kind == .bold)
        #expect(spans[1].kind == .italic)
    }

    @Test("Code before bold: code wins on its range")
    func codeThenBold() {
        let spans = SyntaxHighlighter.parse("`code` **bold**")
        #expect(spans.count == 2)
        #expect(spans[0].kind == .code)
        #expect(spans[1].kind == .bold)
    }
}

// MARK: - Edge Cases

@Suite("SyntaxHighlighter — Edge Cases")
struct EdgeCaseTests {

    @Test("Empty string produces no spans")
    func emptyString() {
        #expect(SyntaxHighlighter.parse("").isEmpty)
    }

    @Test("Plain text produces no spans")
    func plainText() {
        #expect(SyntaxHighlighter.parse("hello world").isEmpty)
    }

    @Test("Unmatched * produces no span")
    func unmatchedStar() {
        #expect(SyntaxHighlighter.parse("*no close").isEmpty)
    }

    @Test("Unmatched ** produces no span")
    func unmatchedDoubleStar() {
        #expect(SyntaxHighlighter.parse("**no close").isEmpty)
    }

    @Test("Adjacent bold spans")
    func adjacentBold() {
        let spans = SyntaxHighlighter.parse("**a** **b**")
        #expect(spans.count == 2)
        #expect(spans[0].kind == .bold)
        #expect(spans[1].kind == .bold)
    }
}

// MARK: - Mismatched Delimiters (CommonMark behavior)
//
// Per CommonMark spec, mismatched delimiters match the smaller count.
// e.g. **hi* → literal * + italic hi (the single * pair matches).
// This matches Apple's AttributedString(markdown:) behavior.

@Suite("SyntaxHighlighter — Mismatched Delimiters")
struct MismatchedDelimiterTests {

    @Test("**hi* → italic hi (single * pair matches, extra * is literal)")
    func doubleOpenSingleClose() {
        let spans = SyntaxHighlighter.parse("**hi*")
        let italics = spans.filter { $0.kind == .italic }
        #expect(italics.count == 1)
    }

    @Test("*hi** → italic hi (single * pair matches, extra * is literal)")
    func singleOpenDoubleClose() {
        let spans = SyntaxHighlighter.parse("*hi**")
        let italics = spans.filter { $0.kind == .italic }
        #expect(italics.count == 1)
    }

    @Test("***hi** → bold hi (double ** pair matches, extra * is literal)")
    func tripleOpenDoubleClose() {
        let spans = SyntaxHighlighter.parse("***hi**")
        let bolds = spans.filter { $0.kind == .bold }
        #expect(bolds.count == 1)
    }

    @Test("***hi* → italic hi (single * pair matches, extra ** is literal)")
    func tripleOpenSingleClose() {
        let spans = SyntaxHighlighter.parse("***hi*")
        let italics = spans.filter { $0.kind == .italic }
        #expect(italics.count == 1)
    }

    @Test("**hi*** → bold hi (double ** pair matches, extra * is literal)")
    func doubleOpenTripleClose() {
        let spans = SyntaxHighlighter.parse("**hi***")
        let bolds = spans.filter { $0.kind == .bold }
        #expect(bolds.count == 1)
    }

    @Test("*hi*** → italic hi (single * pair matches, extra ** is literal)")
    func singleOpenTripleClose() {
        let spans = SyntaxHighlighter.parse("*hi***")
        let italics = spans.filter { $0.kind == .italic }
        #expect(italics.count == 1)
    }
}
