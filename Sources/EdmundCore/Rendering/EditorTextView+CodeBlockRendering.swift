import AppKit

// MARK: - Code Block Rendering
//
// A tinted background box (matching Read mode's `--code-bg`, see
// HTMLTheme.swift) for an inactive *fenced* code block. The fence lines get
// the same treatment as blockquote's `>` marker: normal-size text that draws
// no ink (clear color, NOT hiddenFont — see the delimiter loop in
// EditorTextView+Rendering.swift), so each fence line keeps its natural
// height and doubles as the box's top/bottom breathing room. When the caret
// is inside (cursorInToken), the caller skips this and the raw fences show
// dimmed, exactly like callouts and block quotes. Indented code blocks keep
// their plain monospace rendering — no fence lines to absorb a box's
// breathing room, and no box wanted there.

extension EditorTextView {

    /// Background tint for a code block's box. Matches Read mode's
    /// `--code-bg` (HTMLTheme.swift) so Edit and Read mode agree; a ColaMD
    /// preset paints its own panel (Elegant's dark #2c2c2c).
    var codeBlockBackground: NSColor {
        if let hex = theme.preset.codeBlockBackgroundHex, let color = NSColor(hex: hex) {
            return color
        }
        // ColaMD Light: #f6f8fa, Dark: #161b22 — use sRGB for exact match.
        return isDarkAppearance
            ? NSColor(srgbRed: 0x16 / 255.0, green: 0x1b / 255.0, blue: 0x22 / 255.0, alpha: 1)
            : (NSColor(srgbRed: 0xf6 / 255.0, green: 0xf8 / 255.0, blue: 0xfa / 255.0, alpha: 1))
    }

    /// Base ink for fenced code.  A preset may supply a code-panel-specific
    /// color (Elegant uses warm light text on its dark panel); otherwise code
    /// starts from the editor foreground and syntax highlighting paints tokens.
    var codeBlockTextColor: NSColor {
        if let hex = theme.preset.codeBlockTextHex, let color = NSColor(hex: hex) {
            return color
        }
        return foregroundColor
    }

    /// Applies the background box to an inactive fenced code block. Only
    /// called from styleBlock's `.codeBlock` case when `!cursorInToken`;
    /// the fence ink itself is cleared by the delimiter loop.
    func styleCodeBlockBox(_ result: NSMutableAttributedString,
                           span: SyntaxHighlighter.Span,
                           language: String?) {
        guard span.fullRange.upperBound <= result.length,
              !span.delimiterRanges.isEmpty else { return }
        let vPad = codeBlockVPad
        let box = BlockDecoration(.box(background: codeBlockBackground, borderColor: nil,
                                       borderEdges: [], borderWidth: 0, topPad: vPad,
                                       bottomPad: vPad, cornerRadius: codeCornerRadius))
        result.addAttribute(.blockDecoration, value: box, range: span.fullRange)
        result.addAttribute(.paragraphStyle, value: codeBlockParagraphStyle, range: span.fullRange)
        // A code block must be independent from body tracking.
        result.addAttribute(.kern, value: 0, range: span.fullRange)

        // Label plumbing: the opening fence line carries the display language
        // ("" when the fence names none) and shaves the box's top padding;
        // the second row paints the actual label, reaching up over the fence
        // row (see `.codeBlockLabelAnchor` for why the fence fragment can't).
        let ns = result.string as NSString
        let trimmed = language?.trimmingCharacters(in: .whitespaces) ?? ""
        let firstLine = ns.lineRange(for: NSRange(location: span.fullRange.location, length: 0))
        result.addAttribute(.codeBlockLabel, value: trimmed.capitalized,
                            range: NSIntersectionRange(firstLine, span.fullRange))
        if !trimmed.isEmpty, firstLine.upperBound < span.fullRange.upperBound {
            let secondLine = ns.lineRange(for: NSRange(location: firstLine.upperBound, length: 0))
            result.addAttribute(.codeBlockLabelAnchor, value: trimmed.capitalized,
                                range: NSIntersectionRange(secondLine, span.fullRange))
        }
        // Mark the closing line so its fragment's box draws the block's bottom
        // corners (each row is its own fragment — see `codeBoxPath`).
        let lastChar = max(span.fullRange.location, span.fullRange.upperBound - 1)
        let lastLine = ns.lineRange(for: NSRange(location: lastChar, length: 0))
        if lastLine.location >= span.fullRange.location {
            result.addAttribute(.codeBlockLastLine, value: true,
                                range: NSIntersectionRange(lastLine, span.fullRange))
        }
    }

    /// Text inset for a code block's box (matches Read mode's `pre { padding }`).
    /// No hanging indent — code has no per-line marker to hang under.
    /// Interior code lines use compact spacing (no paragraphSpacingBefore,
    /// tighter lineSpacing) so they tile into one continuous panel rather than
    /// looking like separate rows with gaps between them.
    private var codeBlockParagraphStyle: NSParagraphStyle {
        let ps = NSMutableParagraphStyle()
        // ColaMD uses line-height: 1.6 for code.  The editor's `lineSpacing`
        // is the extra space *between* lines (not a multiplier), so we compute
        // it from the code font size: lineHeight = fontSize + lineSpacing →
        // lineSpacing = fontSize * (1.6 - 1) = fontSize * 0.6.
        let codeLineSpacing = codeBlockFont.pointSize * 0.6
        ps.lineSpacing = codeLineSpacing
        // Zero paragraph spacing so code lines tile seamlessly.
        ps.paragraphSpacingBefore = 0
        ps.paragraphSpacing = 0
        // User-tunable in Settings (default hPad 16).
        let hPad = codeBlockHPad
        ps.firstLineHeadIndent = hPad
        ps.headIndent = hPad
        ps.tailIndent = -hPad
        return ps
    }
}
