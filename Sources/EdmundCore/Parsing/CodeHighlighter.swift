import Foundation

// MARK: - Code Highlighter (facade)
//
// The public entry point for fenced-code-block highlighting and the pluggable
// seam. It owns the shared token model (`Token` / `TokenType`, keyed by
// `CodeSyntaxPalette`) and delegates the actual tokenizing to `activeBackend`.
// The default backend is the lightweight JSON-driven scanner
// (`BuiltinSyntaxBackend`); an "Advanced Code" extension can install a
// Shiki/TextMate backend by assigning `activeBackend` — as long as it maps its
// scopes onto these six `TokenType` cases, Edit mode and Read mode stay identical
// (both consumers call `tokenize` and color from the shared palette).

enum CodeHighlighter {

    enum TokenType: Equatable {
        case keyword, type, string, number, comment, function
    }

    struct Token: Equatable {
        let range: NSRange
        let type: TokenType
    }

    /// The backend that turns code into tokens. Defaults to the built-in scanner;
    /// reassign to plug a different highlighter in behind the same API.
    /// ponytail: main-thread use (rendering / export), like the store it wraps.
    nonisolated(unsafe) static var activeBackend: CodeSyntaxBackend = BuiltinSyntaxBackend(store: .shared)

    /// Tokenize a code block. An empty/absent `language` (an untagged fence) is
    /// resolved to the user's configured default language before dispatch, so a
    /// bare ``` block highlights as whatever "Default code syntax" is set to.
    static func tokenize(_ code: String, language: String?) -> [Token] {
        let raw = language?.trimmingCharacters(in: .whitespaces) ?? ""
        let lang = raw.isEmpty ? SyntaxDefinitionStore.shared.defaultLanguage : raw
        return activeBackend.tokenize(code, language: lang)
    }
}
