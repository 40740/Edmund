import Testing
import AppKit
@testable import EdmundCore

// MARK: - Drag & drop image/file insertion helpers

// `EditorTextView` is a main-actor (AppKit) class, so its static pure path
// helper is actor-isolated; this suite runs on the main actor.
@Suite("Drag & drop — relative path computation")
@MainActor
struct DragDropRelativePathTests {

    @Test("Image in the document folder yields a bare relative path")
    func sameFolderImage() {
        let doc = URL(fileURLWithPath: "/Users/me/notes/note.md")
        let img = URL(fileURLWithPath: "/Users/me/notes/pic.png")
        #expect(EditorTextView.relativePath(from: img, toDirectory: doc.deletingLastPathComponent()) == "pic.png")
    }

    @Test("Image in an images subfolder yields images/…")
    func subfolderImage() {
        let doc = URL(fileURLWithPath: "/Users/me/notes/note.md")
        let img = URL(fileURLWithPath: "/Users/me/notes/images/pic.png")
        #expect(EditorTextView.relativePath(from: img, toDirectory: doc.deletingLastPathComponent()) == "images/pic.png")
    }

    @Test("File outside the document folder falls back to the absolute path")
    func outsideFolder() {
        let doc = URL(fileURLWithPath: "/Users/me/notes/note.md")
        let other = URL(fileURLWithPath: "/Users/other/Downloads/file.md")
        #expect(EditorTextView.relativePath(from: other, toDirectory: doc.deletingLastPathComponent()) == "/Users/other/Downloads/file.md")
    }

    @Test("A file in a sibling directory is absolute (not under the doc folder)")
    func siblingFolder() {
        let doc = URL(fileURLWithPath: "/Users/me/notes/note.md")
        let sibling = URL(fileURLWithPath: "/Users/me/assets/img.png")
        #expect(EditorTextView.relativePath(from: sibling, toDirectory: doc.deletingLastPathComponent()) == "/Users/me/assets/img.png")
    }
}
