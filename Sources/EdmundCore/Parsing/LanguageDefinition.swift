import Foundation

// MARK: - Language Definition
//
// The declarative, per-language data the built-in highlighter reads instead of
// hardcoded sets. Bundled defs ship as JSON under Resources/Syntaxes; users add
// languages by dropping their own JSON in ~/.edmund/syntaxes. JSON (not YAML)
// keeps parsing dependency-free (Codable) and off the render hot path.
//
// The schema is deliberately minimal — the scanner supplies the universal parts
// (numbers, identifiers, Uppercase→type, `ident(`→function). A def only has to
// name its comment style, string delimiters, and keyword/type words.

struct LanguageDefinition: Codable, Equatable {
    /// Canonical lowercase id, e.g. "python". Matched against a fence's info string.
    let name: String
    /// Human label for the settings list; defaults to a capitalized `name`.
    let displayName: String?
    /// Extra info-string spellings that resolve to this def, e.g. ["py"].
    let aliases: [String]
    /// Line-comment lead, e.g. "//", "#", "--". `nil` = language has none.
    let lineComment: String?
    /// `[open, close]` block-comment delimiters, e.g. ["/*", "*/"]. `nil` = none.
    let blockComment: [String]?
    /// Single-character string delimiters. Defaults to `"` and `'`.
    let strings: [String]
    /// Keyword words (control flow, declarations, operators-as-words).
    let keywords: [String]
    /// Type / builtin words colored as types regardless of case.
    let types: [String]

    enum CodingKeys: String, CodingKey {
        case name, displayName, aliases, lineComment, blockComment, strings, keywords, types
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name).lowercased()
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        aliases = (try c.decodeIfPresent([String].self, forKey: .aliases) ?? []).map { $0.lowercased() }
        lineComment = try c.decodeIfPresent(String.self, forKey: .lineComment)
        blockComment = try c.decodeIfPresent([String].self, forKey: .blockComment)
        strings = try c.decodeIfPresent([String].self, forKey: .strings) ?? ["\"", "'"]
        keywords = try c.decodeIfPresent([String].self, forKey: .keywords) ?? []
        types = try c.decodeIfPresent([String].self, forKey: .types) ?? []
    }

    /// Direct init for the built-in fallback def (no JSON round-trip).
    init(name: String, displayName: String? = nil, aliases: [String] = [],
         lineComment: String? = nil, blockComment: [String]? = nil,
         strings: [String] = ["\"", "'"], keywords: [String] = [], types: [String] = []) {
        self.name = name.lowercased()
        self.displayName = displayName
        self.aliases = aliases.map { $0.lowercased() }
        self.lineComment = lineComment
        self.blockComment = blockComment
        self.strings = strings
        self.keywords = keywords
        self.types = types
    }

    /// The label shown in the settings list.
    var label: String { displayName ?? name.capitalized }

    /// The generic C-family def used for a tagged fence whose language has no
    /// definition — preserves the pre-refactor "unknown language still gets the
    /// shared highlighter" behavior. `#`-comment languages have their own defs,
    /// so the fallback only needs the `//` + `/* */` family.
    static let cFamilyFallback = LanguageDefinition(
        name: "", displayName: "", lineComment: "//", blockComment: ["/*", "*/"],
        keywords: [
            "func", "function", "fn", "def", "let", "var", "val", "const", "static",
            "final", "class", "struct", "enum", "interface", "protocol", "trait",
            "impl", "extends", "implements", "namespace", "package", "module", "mod",
            "import", "export", "from", "use", "using", "include", "require",
            "public", "private", "protected", "internal", "fileprivate", "open",
            "if", "else", "elif", "for", "while", "do", "switch", "case", "default",
            "break", "continue", "return", "yield", "goto", "match", "when", "where",
            "try", "catch", "except", "finally", "throw", "throws", "raise", "rescue",
            "guard", "defer", "async", "await", "go", "chan", "select", "with", "as",
            "is", "in", "of", "new", "delete", "typeof", "instanceof", "sizeof",
            "virtual", "override", "abstract", "extension", "init", "self", "this",
            "super", "nil", "null", "none", "undefined", "true", "false", "and",
            "or", "not", "lambda", "pass", "global", "nonlocal", "mut", "pub", "dyn",
            "type", "object", "end", "begin", "then", "elsif", "unless", "until",
        ],
        types: [
            "void", "int", "long", "short", "char", "float", "double", "bool",
            "boolean", "string", "unsigned", "signed", "auto", "typedef", "template",
        ])
}
