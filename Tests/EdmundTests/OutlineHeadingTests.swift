import Testing
import AppKit
@testable import EdmundCore

// MARK: - Outline heading extraction (TOC panel)

// EditorTextView is a main-actor (AppKit) class, so its static parse helper
// and instance outline scan are both actor-isolated; these suites run on the
// main actor.
@Suite("Outline — heading line parsing")
@MainActor
struct OutlineHeadingLineTests {

    @Test("ATX levels 1…6 are recognized")
    func levels() {
        #expect(EditorTextView.parseHeadingLine("# Title")?.level == 1)
        #expect(EditorTextView.parseHeadingLine("## Sub")?.level == 2)
        #expect(EditorTextView.parseHeadingLine("### Deep")?.level == 3)
        #expect(EditorTextView.parseHeadingLine("###### Tiny")?.level == 6)
    }

    @Test("Heading text is stripped of hashes and whitespace")
    func text() {
        let parsed = EditorTextView.parseHeadingLine("##   Hello  ")
        #expect(parsed?.level == 2)
        #expect(parsed?.text == "Hello")
    }

    @Test("Non-heading lines return nil")
    func nonHeadings() {
        #expect(EditorTextView.parseHeadingLine("plain text") == nil)
        #expect(EditorTextView.parseHeadingLine("#NoSpace") == nil)
        #expect(EditorTextView.parseHeadingLine("#") == nil)
        #expect(EditorTextView.parseHeadingLine("###") == nil)
        #expect(EditorTextView.parseHeadingLine("") == nil)
        #expect(EditorTextView.parseHeadingLine("``` # inside code") == nil)
    }
}

@Suite("Outline — document heading scan")
@MainActor
struct OutlineHeadingsTests {

    private func makeEditor(_ text: String) -> EditorTextView {
        let tv = EditorTextView(frame: .zero)
        tv.loadContent(text)
        return tv
    }

    @Test("Collects headings in order with offsets")
    func ordered() {
        let text = "Intro\n\n# First\n\n## Child\n\nBody\n\n# Second\n"
        let tv = makeEditor(text)
        let headings = tv.outlineHeadings()
        #expect(headings.count == 3)
        #expect(headings[0].level == 1)
        #expect(headings[0].text == "First")
        #expect(headings[1].level == 2)
        #expect(headings[1].text == "Child")
        #expect(headings[2].level == 1)
        #expect(headings[2].text == "Second")
        // Offsets point at each heading line's start.
        let ns = text as NSString
        #expect(ns.substring(with: NSRange(location: headings[0].offset, length: 7)) == "# First")
    }

    @Test("Ignores hashes without following space and empty headings")
    func skipsFalsePositives() {
        let text = "#Real\n\n## \n\n# Good\n"
        let tv = makeEditor(text)
        let headings = tv.outlineHeadings()
        #expect(headings.count == 1)
        #expect(headings[0].text == "Good")
    }

    @Test("Empty document yields no headings")
    func empty() {
        let tv = makeEditor("")
        #expect(tv.outlineHeadings().isEmpty)
    }
}
