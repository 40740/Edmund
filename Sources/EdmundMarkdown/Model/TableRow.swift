import Foundation

// MARK: - Table row parsing
//
// `splitTableRow` parses a pipe-delimited markdown row into its cells. It was a
// free function in the editor's table-navigation code, but the *parser* needs it
// too (deciding whether a line is a table's delimiter row), which is why it now
// lives with the model. GFM Example 200 (a `\|` is content, not a separator) is
// the behaviour both callers depend on.

/// Splits a markdown table row into cell strings (text between pipes).
/// Handles both `| A | B |` (outer pipes) and `A | B` (no outer pipes).
/// A `\|` is escaped content, not a cell separator (GFM Example 200).
public func splitTableRow(_ line: String) -> [String] {
    var parts: [String] = []
    var current = ""
    var prevWasBackslash = false
    for ch in line {
        if ch == "|" && !prevWasBackslash {
            parts.append(current)
            current = ""
        } else {
            current.append(ch)
        }
        prevWasBackslash = (ch == "\\") && !prevWasBackslash
    }
    parts.append(current)

    // Remove empty/whitespace-only first/last from outer pipes.
    if let first = parts.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
        parts.removeFirst()
    }
    if let last = parts.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
        parts.removeLast()
    }
    return parts
}
