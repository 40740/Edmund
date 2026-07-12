import Foundation

/// Incremental backing for the document's link reference definitions.
///
/// GFM reference links (`[text][label]`, `[label][]`, `[label]`) resolve
/// against `[label]: destination` definitions that may live in *other* blocks.
/// Edmund styles one block at a time, so the editor collects every definition
/// line here — built whole-document on load and maintained per changed block on
/// the edit path (mirroring `ListIndentState`) — and appends `defsText` to each
/// block's parse so swift-markdown's CommonMark parser resolves the references
/// (see `SyntaxHighlighter.parse(_:linkDefinitions:)`).
///
/// A multiset of the raw definition *lines* is enough: swift-markdown applies
/// CommonMark's "first definition wins" itself, and `defsText` is sorted so the
/// incremental state and a from-scratch rebuild always produce the identical
/// string (the full-recompose oracle depends on that determinism).
struct LinkDefinitionState: Equatable {
    /// Unique `[label]: url` source lines → occurrence count, so per-block
    /// add/remove stays exact when the same line appears more than once.
    private var lines: [String: Int] = [:]

    /// The collected definition lines, sorted and newline-joined. Empty when the
    /// document defines no references (then parsing skips the append entirely).
    var defsText: String { lines.keys.sorted().joined(separator: "\n") }

    mutating func add(_ content: String) { scan(content, sign: 1) }
    mutating func remove(_ content: String) { scan(content, sign: -1) }

    static func build(from source: String) -> LinkDefinitionState {
        var state = LinkDefinitionState()
        state.add(source)
        return state
    }

    private mutating func scan(_ content: String, sign: Int) {
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let key = String(line)
            guard Self.isDefinitionLine(key) else { continue }
            let count = (lines[key] ?? 0) + sign
            lines[key] = count <= 0 ? nil : count
        }
    }

    /// A CommonMark link reference definition line: up to 3 leading spaces, a
    /// non-empty `[label]`, `:`, then a destination. (Rare multi-line / titled
    /// forms aren't recognized; ponytail: single-line covers the common case.)
    private static let defRegex = try! NSRegularExpression(
        pattern: #"^ {0,3}\[[^\]\n]+\]:\s*\S.*$"#)

    static func isDefinitionLine(_ line: String) -> Bool {
        defRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }
}
