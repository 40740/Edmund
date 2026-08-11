import AppKit

// MARK: - Code Block Syntax Highlighting
//
// Colors a fenced code block's content from `CodeHighlighter` tokens, using the
// Tomorrow palette in light appearance and One Dark in dark. Only foregrounds
// are themed — the block keeps the editor's background — so each palette is
// paired with the appearance whose background it's legible on.

extension EditorTextView {

    private var prefersDarkCodeTheme: Bool {
        // Elegant deliberately uses a dark code panel even though the preset
        // itself forces the app into a light appearance.  Therefore syntax
        // highlighting must follow the *code panel*, not the window appearance.
        switch theme.preset {
        case .colaDark, .colaElegant:
            return true
        case .colaLight, .colaNewsprint:
            return false
        case .system:
            return effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
    }

    /// The `NSColor` for a token kind (`nil` = plain code) in the current
    /// appearance, derived from the shared `CodeSyntaxPalette` hexes so the
    /// editor and Read mode / PDF export color tokens identically. A ColaMD
    /// preset overrides the plain ink (Elegant's light #e0dcd7 on its dark
    /// panel); token colors stay on the shared palette so syntax still pops.
    private func codeColor(_ type: CodeHighlighter.TokenType?) -> NSColor {
        if type == nil, let hex = theme.preset.codeBlockTextHex,
           let color = NSColor(hex: hex) { return color }
        return NSColor(hex: CodeSyntaxPalette.hex(type, dark: prefersDarkCodeTheme)) ?? .textColor
    }

    /// Applies syntax colors to a code block's content range in place.
    func highlightCodeBlock(_ result: NSMutableAttributedString,
                            contentRange: NSRange, language: String?) {
        guard contentRange.length > 0, contentRange.upperBound <= result.length else { return }

        // Plain code text first; token colors paint over it.
        result.addAttribute(.foregroundColor, value: codeColor(nil), range: contentRange)

        let code = (result.string as NSString).substring(with: contentRange)
        for token in CodeHighlighter.tokenize(code, language: language) {
            let abs = NSRange(location: contentRange.location + token.range.location,
                              length: token.range.length)
            guard abs.upperBound <= result.length else { continue }
            result.addAttribute(.foregroundColor, value: codeColor(token.type), range: abs)
        }
    }
}
