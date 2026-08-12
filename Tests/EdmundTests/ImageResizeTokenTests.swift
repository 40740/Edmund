import XCTest
@testable import EdmundCore

/// Tests for the lightweight image drag-to-resize feature's pure string
/// helpers: image-token scanning, destination extraction, and the width
/// parsing used by the resize handle.
@MainActor
final class ImageResizeTokenTests: XCTestCase {

    /// Build an editor whose rawSource is the given markdown. The helper
    /// methods under test (`imageTokenRange(containing:)`,
    /// `imageDestination(for:)`, `imageRange(forDestination:)`,
    /// `imageCurrentWidth(destination:)`) operate on `rawSource` alone and
    /// don't need a live layout, so a minimal NSTextView subclass suffices.
    private func makeEditor(source: String) -> EditorTextView {
        let tv = EditorTextView()
        tv.rawSource = source
        return tv
    }

    // MARK: - imageTokenRange(containing:)

    func testFindsMarkdownImageToken() throws {
        let src = "text ![alt](img.png) more"
        let editor = makeEditor(source: src)
        let ns = src as NSString
        // The `!` of `![alt](img.png)` is at offset 5.
        let range = editor.imageTokenRange(containing: 5)
        XCTAssertEqual(range, NSRange(location: 5, length: 15), "should find the ![alt](img.png) token")
        // Inside the parentheses.
        XCTAssertEqual(editor.imageTokenRange(containing: 10), range)
    }

    func testFindsHTMLImageToken() throws {
        let src = #"text <img src="img.png" width="100"> more"#
        let editor = makeEditor(source: src)
        let ns = src as NSString
        let range = editor.imageTokenRange(containing: 6)
        XCTAssertEqual(range, NSRange(location: 5, length: (src as NSString).range(of: #"<img src="img.png" width="100">"#).length),
                       "should find the <img> token")
    }

    func testFindsObsidianEmbedToken() throws {
        let src = "text ![[img.png|200]] more"
        let editor = makeEditor(source: src)
        let range = editor.imageTokenRange(containing: 5)
        XCTAssertEqual(range?.location, 5)
        XCTAssertEqual(range?.length, (src as NSString).range(of: "![[img.png|200]]").length)
    }

    func testReturnsNilWhenNotOverImage() throws {
        let src = "just plain text"
        let editor = makeEditor(source: src)
        XCTAssertNil(editor.imageTokenRange(containing: 2))
    }

    // MARK: - imageDestination(for:)

    func testDestinationFromMarkdown() throws {
        let src = "text ![alt](img.png) more"
        let editor = makeEditor(source: src)
        XCTAssertEqual(editor.imageDestination(for: 5), "img.png")
    }

    func testDestinationFromHTML() throws {
        let src = #"<img src="images/pic.jpg" width="200">"#
        let editor = makeEditor(source: src)
        XCTAssertEqual(editor.imageDestination(for: 1), "images/pic.jpg")
    }

    func testDestinationFromObsidianEmbed() throws {
        let src = "![[notes/img.png|300]]"
        let editor = makeEditor(source: src)
        XCTAssertEqual(editor.imageDestination(for: 1), "notes/img.png")
    }

    // MARK: - imageRange(forDestination:)

    func testFindRangeByDestination() throws {
        let src = "![first](a.png) then ![second](b.png)"
        let editor = makeEditor(source: src)
        let ns = src as NSString
        let range = editor.imageRange(forDestination: "b.png")
        XCTAssertNotNil(range)
        XCTAssertEqual(ns.substring(with: range!), "![second](b.png)")
    }

    func testFindRangeForHTMLDestination() throws {
        let src = #"<img src="pic.png" width="120">"#
        let editor = makeEditor(source: src)
        XCTAssertNotNil(editor.imageRange(forDestination: "pic.png"))
    }

    func testFindRangeForObsidianDestination() throws {
        let src = "![[folder/img|200]]"
        let editor = makeEditor(source: src)
        XCTAssertNotNil(editor.imageRange(forDestination: "folder/img"))
    }

    // MARK: - imageCurrentWidth(destination:)

    func testCurrentWidthFromHTML() throws {
        let src = #"<img src="pic.png" width="200" height="150">"#
        let editor = makeEditor(source: src)
        XCTAssertEqual(editor.imageCurrentWidth(destination: "pic.png"), 200)
    }

    func testCurrentWidthFromObsidian() throws {
        let src = "![[img.png|300]]"
        let editor = makeEditor(source: src)
        XCTAssertEqual(editor.imageCurrentWidth(destination: "img.png"), 300)
    }

    func testCurrentWidthNilWhenNoDimension() throws {
        let src = "![alt](img.png)"
        let editor = makeEditor(source: src)
        XCTAssertNil(editor.imageCurrentWidth(destination: "img.png"))
    }
}
