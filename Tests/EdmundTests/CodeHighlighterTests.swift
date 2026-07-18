import Testing
import Foundation
@testable import EdmundCore

@Suite("CodeHighlighter")
struct CodeHighlighterTests {

    private func tokens(_ code: String, _ lang: String?) -> [(text: String, type: CodeHighlighter.TokenType)] {
        let ns = code as NSString
        return CodeHighlighter.tokenize(code, language: lang).map {
            (ns.substring(with: $0.range), $0.type)
        }
    }

    @Test("Recognizes keywords, functions, numbers, strings, comments")
    func swiftTokens() {
        let t = tokens("// hi\nfunc greet() { let n = 42; return \"x\" }", "swift")
        #expect(t.contains { $0.text == "// hi" && $0.type == .comment })
        #expect(t.contains { $0.text == "func" && $0.type == .keyword })
        #expect(t.contains { $0.text == "greet" && $0.type == .function })
        #expect(t.contains { $0.text == "let" && $0.type == .keyword })
        #expect(t.contains { $0.text == "42" && $0.type == .number })
        #expect(t.contains { $0.text == "\"x\"" && $0.type == .string })
    }

    @Test("# starts a comment in hash-comment languages only")
    func hashComment() {
        #expect(tokens("# note", "python").contains { $0.type == .comment })
        #expect(!tokens("# note", "swift").contains { $0.type == .comment })
    }

    @Test("Capitalized identifier is typed as a type")
    func typeToken() {
        #expect(tokens("let x: String = y", "swift").contains { $0.text == "String" && $0.type == .type })
    }

    @Test("Block comments span across lines")
    func blockComment() {
        let t = tokens("a /* multi\nline */ b", "c")
        #expect(t.contains { $0.text == "/* multi\nline */" && $0.type == .comment })
    }

    @Test("An alias resolves to its language definition")
    func aliasResolves() {
        // "py" → python, so `def` is a keyword and `#` starts a comment.
        let t = tokens("# c\ndef f(): pass", "py")
        #expect(t.contains { $0.text == "# c" && $0.type == .comment })
        #expect(t.contains { $0.text == "def" && $0.type == .keyword })
    }

    @Test("An unknown language falls back to the C-family highlighter")
    func unknownFallback() {
        let t = tokens("func x() { return 1 }", "no-such-lang")
        #expect(t.contains { $0.text == "func" && $0.type == .keyword })
        #expect(t.contains { $0.text == "1" && $0.type == .number })
    }

    @Test("Plain languages produce no tokens")
    func plainIsEmpty() {
        for lang in ["plain", "text", "none", "txt"] {
            #expect(CodeHighlighter.tokenize("func x = 1", language: lang).isEmpty)
        }
    }

    @Test("The scanner uses the definition's comment style")
    func customDefinition() {
        let def = LanguageDefinition(
            name: "toy", lineComment: "--", keywords: ["let"])
        let ns = "-- note\nlet x = 1" as NSString
        let t: [(text: String, type: CodeHighlighter.TokenType)] =
            BuiltinSyntaxBackend.scan(ns as String, def).map {
                (text: ns.substring(with: $0.range), type: $0.type)
            }
        #expect(t.contains { $0.text == "-- note" && $0.type == .comment })
        #expect(t.contains { $0.text == "let" && $0.type == .keyword })
    }
}

@Suite("SyntaxDefinitionStore", .serialized)
struct SyntaxDefinitionStoreTests {

    @Test("Bundled definitions load and aliases resolve")
    func bundledLoads() {
        let store = SyntaxDefinitionStore()
        guard case .definition(let def) = store.resolve("py") else {
            Issue.record("py did not resolve to a definition"); return
        }
        #expect(def.name == "python")
        #expect(store.resolve("") == .plain)
        #expect(store.resolve("no-such-lang") == .unknown)
    }

    @Test("Plain Text leads the available list")
    func availableList() {
        let ids = SyntaxDefinitionStore().availableLanguages().map(\.id)
        #expect(ids.first == "plain")
        #expect(ids.contains("swift"))
    }

    @Test("An untagged fence highlights as the default language")
    func defaultLanguageSubstitution() {
        let store = SyntaxDefinitionStore.shared
        let saved = store.defaultLanguage
        defer { store.defaultLanguage = saved }

        store.defaultLanguage = "python"
        // No language → resolved to python, so `#` starts a comment.
        #expect(CodeHighlighter.tokenize("# hi", language: nil)
            .contains { $0.type == .comment })

        store.defaultLanguage = "plain"
        #expect(CodeHighlighter.tokenize("# hi", language: nil).isEmpty)
    }
}
