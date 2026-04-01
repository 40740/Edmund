import Foundation

/// Splits a document string into `Block`s and preserves block identity
/// across re-parses so the "active block" doesn't jump around.
///
/// Strategy:
///   1. Split the raw string on single newlines (`\n`) to get paragraphs.
///   2. Compute each paragraph's `NSRange` within the full string.
///   3. Match new paragraphs to previous blocks by content equality to
///      preserve UUIDs.  Unmatched paragraphs get fresh UUIDs.
enum BlockParser {

    static func parse(_ text: String, previous: [Block] = []) -> [Block] {
        let nsText = text as NSString
        let paragraphs = splitParagraphs(text)

        var available = previous
        var blocks: [Block] = []
        var cursor = 0

        for para in paragraphs {
            let length = (para as NSString).length
            let range = NSRange(location: cursor, length: length)

            let id: UUID
            if let idx = available.firstIndex(where: { $0.content == para }) {
                id = available[idx].id
                available.remove(at: idx)
            } else {
                id = UUID()
            }

            blocks.append(Block(id: id, content: para, range: range))

            // Advance past this paragraph.
            cursor = range.upperBound
            // Skip the single \n separator (if present).
            if cursor < nsText.length && nsText.character(at: cursor) == UInt16(0x0A) {
                cursor += 1
            }
        }

        return blocks
    }

    // MARK: - Helpers

    /// Splits text into paragraphs on single newlines.
    private static func splitParagraphs(_ text: String) -> [String] {
        if text.isEmpty { return [""] }

        // Split on each \n.  This gives us one block per line.
        let parts = text.components(separatedBy: "\n")

        // If the text ends with \n, components(separatedBy:) produces a
        // trailing empty string.  Keep it — it represents the new empty
        // block the user just created by pressing Enter.
        return parts
    }
}
