import AppKit

// MARK: - ColaMD Preset Rendering Colors (Edit mode)
//
// Edit mode renders everything as NSAttributedString attributes + TextKit 2
// fragment decorations — no CSS. The historical Edmund look hardcodes a small
// palette of system semantic colors and sRGB grays (syntaxDimColor,
// inlineCodeBackground, codeBlockBackground, darkChromeGray, …). The ColaMD
// "Elegant Plus" preset has its own palette (terracotta accent, warm-paper
// code chip, dark code panel) that can't be expressed as a recolor of the
// Edmund defaults.
//
// This extension provides preset-aware alternatives for every rendering
// decision that differs between the two looks. Each property returns the
// ColaMD value when `theme.preset == .colaElegant`, and falls through to the
// historical Edmund value otherwise — so the Edmund path is untouched.
//
// Colors are built with `srgbRed:`, NOT `NSColor(hex:)` or
// `calibratedWhite:` — the calibrated space renders visibly lighter than the
// sRGB hex once composited on screen (same trap `editorBackgroundColor`
// documents). The hexes come from `UI-设计文档.md` §2.
extension EditorTextView {

    // MARK: - Bold / emphasis

    /// Bold-text ink. Edmund paints bold in the body color (the font weight
    /// change alone carries the emphasis); ColaMD's design doc (§4 — "Strong -
    /// Accent Color") uses the terracotta accent for bold so a single accent
    /// color spans bold, links, quotes, code, and marks.
    var boldTextColor: NSColor {
        switch theme.preset {
        case .edmund:
            return foregroundColor
        case .colaElegant:
            return isDarkAppearance
                ? NSColor(srgbRed: 0xe0 / 255.0, green: 0x65 / 255.0, blue: 0x3f / 255.0, alpha: 1)
                : NSColor(srgbRed: 0xc4 / 255.0, green: 0x4b / 255.0, blue: 0x2b / 255.0, alpha: 1)
        }
    }

    // MARK: - Inline code

    /// Background tint for inline code spans. Edmund uses a 10% neutral wash;
    /// ColaMD uses a warm-paper chip (`#e8e4df` light / `#2a2622` dark —
    /// UI-设计文档.md §4.3) so the code chip reads as a paper tile, not a
    /// gray smudge.
    var presetInlineCodeBackground: NSColor {
        switch theme.preset {
        case .edmund:
            return NSColor(calibratedWhite: 0.5, alpha: isDarkAppearance ? 0.22 : 0.1)
        case .colaElegant:
            return isDarkAppearance
                ? NSColor(srgbRed: 0x2a / 255.0, green: 0x26 / 255.0, blue: 0x22 / 255.0, alpha: 1)
                : NSColor(srgbRed: 0xe8 / 255.0, green: 0xe4 / 255.0, blue: 0xdf / 255.0, alpha: 1)
        }
    }

    /// Ink for inline code text. Edmund paints inline code in the body color;
    /// ColaMD paints it in the terracotta accent (UI-设计文档.md §4.3 —
    /// `color: #c44b2b`) so the chip + text form a single accent token.
    var presetInlineCodeColor: NSColor {
        switch theme.preset {
        case .edmund:
            return foregroundColor
        case .colaElegant:
            return isDarkAppearance
                ? NSColor(srgbRed: 0xe0 / 255.0, green: 0x65 / 255.0, blue: 0x3f / 255.0, alpha: 1)
                : NSColor(srgbRed: 0xc4 / 255.0, green: 0x4b / 255.0, blue: 0x2b / 255.0, alpha: 1)
        }
    }

    // MARK: - Highlight (==mark==)

    /// Background for `==highlight==` spans. Edmund uses a 30% yellow wash;
    /// ColaMD uses a 15% terracotta tint (UI-设计文档.md §4.4 —
    /// `background: rgba(196, 75, 43, 0.15)`) so the highlight reads as a warm
    /// accent wash, not a default browser yellow.
    var presetHighlightBackground: NSColor {
        switch theme.preset {
        case .edmund:
            return NSColor.systemYellow.withAlphaComponent(0.3)
        case .colaElegant:
            return isDarkAppearance
                ? NSColor(srgbRed: 0xe0 / 255.0, green: 0x65 / 255.0, blue: 0x3f / 255.0, alpha: 0.18)
                : NSColor(srgbRed: 0xc4 / 255.0, green: 0x4b / 255.0, blue: 0x2b / 255.0, alpha: 0.15)
        }
    }

    // MARK: - Blockquote bar

    /// Color for the blockquote's left bar. Edmund uses `syntaxDimColor` (a
    /// gray); ColaMD uses the terracotta accent (UI-设计文档.md §4.5 —
    /// `border-left: 4px solid #c44b2b`) so the quote bar carries the same
    /// accent language as bold/links/code.
    var presetQuoteBarColor: NSColor {
        switch theme.preset {
        case .edmund:
            return syntaxDimColor
        case .colaElegant:
            return isDarkAppearance
                ? NSColor(srgbRed: 0xe0 / 255.0, green: 0x65 / 255.0, blue: 0x3f / 255.0, alpha: 1)
                : NSColor(srgbRed: 0xc4 / 255.0, green: 0x4b / 255.0, blue: 0x2b / 255.0, alpha: 1)
        }
    }

    /// Width of the blockquote's left bar. Edmund uses 2pt; ColaMD uses 4pt
    /// (UI-设计文档.md §4.5).
    var presetQuoteBarWidth: CGFloat {
        switch theme.preset {
        case .edmund:        return 2
        case .colaElegant:   return 4
        }
    }

    /// Background fill for the blockquote box. Edmund leaves the quote
    /// transparent (the bar alone delimits it); ColaMD fills it with a soft
    /// paper tint (UI-设计文档.md §4.5 — `background: #eae6e1` light /
    /// `#26231f` dark) so the quote reads as a panel, not just a bar.
    var presetQuoteBackground: NSColor? {
        switch theme.preset {
        case .edmund:
            return nil
        case .colaElegant:
            return isDarkAppearance
                ? NSColor(srgbRed: 0x26 / 255.0, green: 0x23 / 255.0, blue: 0x1f / 255.0, alpha: 1)
                : NSColor(srgbRed: 0xea / 255.0, green: 0xe6 / 255.0, blue: 0xe1 / 255.0, alpha: 1)
        }
    }

    /// Ink for the blockquote's text. Edmund uses `secondaryLabelColor` (a
    /// dim gray); ColaMD uses a warm gray (`#555` light / `#a89f96` dark —
    /// UI-设计文档.md §2) that harmonizes with the paper background.
    var presetQuoteTextColor: NSColor {
        switch theme.preset {
        case .edmund:
            return .secondaryLabelColor
        case .colaElegant:
            return isDarkAppearance
                ? NSColor(srgbRed: 0xa8 / 255.0, green: 0x9f / 255.0, blue: 0x96 / 255.0, alpha: 1)
                : NSColor(srgbRed: 0x55 / 255.0, green: 0x55 / 255.0, blue: 0x55 / 255.0, alpha: 1)
        }
    }

    // MARK: - Code block panel

    /// Background for fenced code blocks. Edmund uses a light gray (`#f4f4f4`)
    /// / dark gray (`#333333`); ColaMD uses a dark panel in BOTH appearances
    /// (UI-设计文档.md §4.2 — `#2c2c2c` light / `#14110f` dark) — the
    /// "technical counterpoint" to the literary serif body.
    var presetCodeBlockBackground: NSColor {
        switch theme.preset {
        case .edmund:
            return isDarkAppearance
                ? NSColor(srgbRed: 0x33 / 255.0, green: 0x33 / 255.0, blue: 0x33 / 255.0, alpha: 1)
                : (NSColor(hex: "#f4f4f4") ?? NSColor(calibratedWhite: 0.96, alpha: 1))
        case .colaElegant:
            return isDarkAppearance
                ? NSColor(srgbRed: 0x14 / 255.0, green: 0x11 / 255.0, blue: 0x0f / 255.0, alpha: 1)
                : NSColor(srgbRed: 0x2c / 255.0, green: 0x2c / 255.0, blue: 0x2c / 255.0, alpha: 1)
        }
    }

    /// Ink for code-block text. Edmund uses the body foreground; ColaMD uses a
    /// warm off-white (`#e0dcd7` — UI-设计文档.md §2.1) so the dark panel's
    /// text reads as paper, not as pure white glare.
    var presetCodeBlockTextColor: NSColor {
        switch theme.preset {
        case .edmund:
            return foregroundColor
        case .colaElegant:
            return NSColor(srgbRed: 0xe0 / 255.0, green: 0xdc / 255.0, blue: 0xd7 / 255.0, alpha: 1)
        }
    }

    // MARK: - Table

    /// Border color for table cell borders. Edmund uses `syntaxDimColor` /
    /// `darkRuleGray`; ColaMD uses a warm border (`#d8d3ce` light / `#3a342e`
    /// dark — UI-设计文档.md §2) that matches the paper palette.
    var presetTableBorderColor: NSColor {
        switch theme.preset {
        case .edmund:
            return isDarkAppearance ? Self.darkRuleGray : .separatorColor
        case .colaElegant:
            return isDarkAppearance
                ? NSColor(srgbRed: 0x3a / 255.0, green: 0x34 / 255.0, blue: 0x2e / 255.0, alpha: 1)
                : NSColor(srgbRed: 0xd8 / 255.0, green: 0xd3 / 255.0, blue: 0xce / 255.0, alpha: 1)
        }
    }

    /// Background tint for the table header row. Edmund leaves it transparent;
    /// ColaMD fills it with the soft paper tint (UI-设计文档.md §4.6 —
    /// `background: #eae6e1`) so the header reads as a distinct band.
    var presetTableHeaderBackground: NSColor? {
        switch theme.preset {
        case .edmund:
            return nil
        case .colaElegant:
            return isDarkAppearance
                ? NSColor(srgbRed: 0x26 / 255.0, green: 0x23 / 255.0, blue: 0x1f / 255.0, alpha: 1)
                : NSColor(srgbRed: 0xea / 255.0, green: 0xe6 / 255.0, blue: 0xe1 / 255.0, alpha: 1)
        }
    }

    /// Color for the header row's bottom border (under the header cells).
    /// Edmund uses the same border as the rest of the table; ColaMD uses a 2pt
    /// terracotta underline (UI-设计文档.md §4.6 —
    /// `border-bottom: 2px solid #c44b2b`) so the header reads as anchored.
    var presetTableHeaderBorderColor: NSColor {
        switch theme.preset {
        case .edmund:
            return presetTableBorderColor
        case .colaElegant:
            return isDarkAppearance
                ? NSColor(srgbRed: 0xe0 / 255.0, green: 0x65 / 255.0, blue: 0x3f / 255.0, alpha: 1)
                : NSColor(srgbRed: 0xc4 / 255.0, green: 0x4b / 255.0, blue: 0x2b / 255.0, alpha: 1)
        }
    }

    // MARK: - Heading

    /// Ink for heading text. Edmund uses the body foreground; ColaMD uses a
    /// deeper ink (`#1a1a1a` light / `#e0dcd7` dark — UI-设计文档.md §2) so
    /// headings read as one step darker than the body.
    var presetHeadingColor: NSColor {
        switch theme.preset {
        case .edmund:
            return foregroundColor
        case .colaElegant:
            return isDarkAppearance
                ? NSColor(srgbRed: 0xe0 / 255.0, green: 0xdc / 255.0, blue: 0xd7 / 255.0, alpha: 1)
                : NSColor(srgbRed: 0x1a / 255.0, green: 0x1a / 255.0, blue: 0x1a / 255.0, alpha: 1)
        }
    }
}
