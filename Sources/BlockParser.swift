import Foundation

/// Splits a document string into `Block`s and preserves block identity
/// across re-parses so the "active block" doesn't jump around.
///
/// Strategy:
///   1. Split the raw string on double-newlines (`\n\n`) to get paragraphs.
///   2. Compute each paragraph's `NSRange` within the full string.
///   3. Match new paragraphs to previous blocks by content equality to
///      preserve UUIDs.  Unmatched paragraphs get fresh UUIDs.
///
/// This is intentionally simple — O(n·m) matching where n,m are block counts.
/// For a typical document (< 1000 paragraphs) this is sub-millisecond.
enum BlockParser {

    static func parse(_ text: String, previous: [Block] = []) -> [Block] {
        // Split on one or more blank lines (two+ consecutive newlines).
        // We keep the separators so we can compute accurate ranges.
        let nsText = text as NSString
        let paragraphs = splitParagraphs(text)

        // Build a bag of previous blocks we can match against.
        // Once a previous block is matched, remove it so each is used at most once.
        var available = previous

        var blocks: [Block] = []
        var cursor = 0  // character offset into the full string

        for para in paragraphs {
            let length = (para as NSString).length
            let range = NSRange(location: cursor, length: length)

            // Try to find a previous block with the same content to reuse its id.
            let id: UUID
            if let idx = available.firstIndex(where: { $0.content == para }) {
                id = available[idx].id
                available.remove(at: idx)
            } else {
                id = UUID()
            }

            blocks.append(Block(id: id, content: para, range: range))

            // Advance cursor past this paragraph + the separator that follows it.
            cursor = range.upperBound
            // Skip any separator characters (\n\n) between paragraphs.
            cursor = skipSeparator(in: nsText, from: cursor)
        }

        return blocks
    }

    // MARK: - Helpers

    /// Splits text into paragraphs on blank lines (\n\n or more).
    /// Returns the content of each paragraph (without the separating blank lines).
    private static func splitParagraphs(_ text: String) -> [String] {
        if text.isEmpty { return [""] }

        // Split on runs of 2+ newlines.
        let pattern = #"\n{2,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [text]
        }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: fullRange)

        if matches.isEmpty {
            return [text]
        }

        var paragraphs: [String] = []
        var start = 0
        for match in matches {
            let paraRange = NSRange(location: start, length: match.range.location - start)
            paragraphs.append(nsText.substring(with: paraRange))
            start = match.range.upperBound
        }
        // Trailing paragraph after the last separator.
        if start <= nsText.length {
            let trailing = nsText.substring(from: start)
            paragraphs.append(trailing)
        }

        return paragraphs
    }

    /// Advance past any run of newlines starting at `from`.
    private static func skipSeparator(in text: NSString, from: Int) -> Int {
        var i = from
        while i < text.length && text.character(at: i) == UInt16(0x0A) /* \n */ {
            i += 1
        }
        return i
    }
}
