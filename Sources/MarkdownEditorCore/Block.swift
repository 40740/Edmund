import Foundation

/// A Block is one paragraph of markdown — the unit of rendering.
///
/// Blocks are separated by newlines (`\n`).  Each block carries:
///   - `id`:       stable UUID so we can track which block the cursor is in
///   - `content`:  the raw markdown text of this paragraph
///   - `range`:    the character range within the full document string
///
/// The editor renders every block as rich text *except* the one containing
/// the cursor, which stays as raw markdown so the user can edit it.
public struct Block: Identifiable, Sendable {
    public let id: UUID
    public var content: String
    public var range: NSRange

    public init(id: UUID = UUID(), content: String, range: NSRange) {
        self.id = id
        self.content = content
        self.range = range
    }
}
