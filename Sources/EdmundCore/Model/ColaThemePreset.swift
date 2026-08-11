import Foundation

/// ColaMD-style theme presets, ported from ColaMD's Light / Dark / Elegant /
/// Newsprint themes.
///
/// `.system` keeps Edmund's default behaviour: follow the OS appearance and the
/// user's own font/colour choices. A ColaMD preset layers a complete palette on
/// top — forced light/dark appearance, background, ink, link/code colours and a
/// matching body font — without mutating the user's saved `EditorTheme`, so
/// switching presets (or back to System) never destroys their customisations.
public enum ColaThemePreset: String, CaseIterable, Identifiable, Sendable {
    case system
    case colaLight
    case colaDark
    case colaElegant
    case colaNewsprint
    case elegantPlus

    public var id: String { rawValue }

    /// Display name shown in the Settings ▸ Appearance picker.
    public var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .colaLight: return "ColaMD 浅色"
        case .colaDark: return "ColaMD 深色"
        case .colaElegant: return "ColaMD 优雅"
        case .colaNewsprint: return "ColaMD 新闻纸"
        case .elegantPlus: return "优雅 Plus"
    }

    /// Whether this preset forces a dark appearance (`.system` is nil).
    public var forcedDark: Bool? {
        switch self {
        case .system: return nil
        case .colaDark: return true
        case .colaLight, .colaElegant, .colaNewsprint, .elegantPlus: return false
        }
    }

    /// Editor page background hex, or nil to keep the appearance default.
    public var backgroundColorHex: String? {
        switch self {
        case .system: return nil
        case .colaLight: return "#ffffff"
        case .colaDark: return "#0d1117"
        case .colaElegant: return "#f0edea"
        case .colaNewsprint: return "#f5f2eb"
        case .elegantPlus: return "#f0edea"
        }
    }

    /// Body ink hex, or nil to keep the appearance default.
    public var textColorHex: String? {
        switch self {
        case .system: return nil
        case .colaLight: return "#24292f"
        case .colaDark: return "#e6edf3"
        case .colaElegant: return "#2c2c2c"
        case .colaNewsprint: return "#1a1a1a"
        case .elegantPlus: return "#2c2c2c"
        }
    }

    /// Link colour hex (overrides the theme's `linkBlueHex`).
    public var linkColorHex: String? {
        switch self {
        case .system: return nil
        case .colaLight: return "#0969da"
        case .colaDark: return "#58a6ff"
        case .colaElegant: return "#c44b2b"
        case .colaNewsprint: return "#2c5f8a"
        case .elegantPlus: return "#c44b2b"
        }
    }

    /// Inline-code ink hex. ColaMD only tints inline code in Elegant (red);
    /// Light / Dark / Newsprint leave it at the body ink.
    public var codeColorHex: String? {
        switch self {
        case .colaElegant, .elegantPlus: return "#c44b2b"
        default: return nil
        }
    }

    /// Bold (**strong**) ink hex, or nil to keep the body color. ColaMD's
    /// signature: Elegant paints bold text in the accent red.
    public var strongColorHex: String? {
        switch self {
        case .colaElegant, .elegantPlus: return "#c44b2b"
        default: return nil
        }
    }

    /// Blockquote left-bar hex.
    public var quoteBarHex: String? {
        switch self {
        case .colaLight: return "#d0d7de"
        case .colaDark: return "#30363d"
        case .colaElegant: return "#c44b2b"
        case .colaNewsprint: return "#999999"
        case .elegantPlus: return "#c44b2b"
        case .system: return nil
        }
    }

    /// Blockquote background fill hex, or nil for none. Elegant paints the
    /// whole quote on a soft paper panel.
    public var quoteBackgroundHex: String? {
        switch self {
        case .colaElegant, .elegantPlus: return "#eae6e1"
        default: return nil
        }
    }

    /// Blockquote text hex (ColaMD's per-theme `--text-muted`).
    public var quoteTextHex: String? {
        switch self {
        case .colaLight: return "#656d76"
        case .colaDark: return "#8b949e"
        case .colaElegant: return "#777777"
        case .colaNewsprint: return "#666666"
        case .elegantPlus: return "#555555"
        case .system: return nil
        }
    }

    /// Table header bottom-rule accent hex, or nil for the default border.
    /// Elegant draws a 2px red rule under the header row.
    public var tableHeadAccentHex: String? {
        switch self {
        case .colaElegant, .elegantPlus: return "#c44b2b"
        default: return nil
        }
    }

    /// Fenced code block background hex (ColaMD's `--code-block-bg`). Elegant's
    /// signature is a dark panel behind the code.
    public var codeBlockBackgroundHex: String? {
        switch self {
        case .colaLight: return "#f6f8fa"
        case .colaDark: return "#161b22"
        case .colaElegant: return "#2c2c2c"
        case .colaNewsprint: return "#eae6de"
        case .elegantPlus: return "#2c2c2c"
        case .system: return nil
        }
    }

    /// Fenced code block text hex (ColaMD's `--code-block-text`), or nil to
    /// keep the body ink. Elegant uses light ink on its dark panel.
    public var codeBlockTextHex: String? {
        switch self {
        case .colaElegant, .elegantPlus: return "#e0dcd7"
        default: return nil
        }
    }

    /// Inline-code background hex, or nil for the default wash. Elegant uses a
    /// light paper chip (its `--code-bg`), distinct from the dark block panel.
    public var inlineCodeBackgroundHex: String? {
        switch self {
        case .colaElegant, .elegantPlus: return "#e8e4df"
        default: return nil
        }
    }

    /// Letter-spacing for body text. Elegant widens it slightly (0.03em) so
    /// Chinese and Latin characters both breathe; other presets keep `normal`.
    public var letterSpacing: String? {
        switch self {
        case .colaElegant: return "0.03em"
        case .elegantPlus: return "0.04em"
        default: return nil
        }
    }

    /// Mark/highlight background. Elegant tints it in the soft accent red
    /// (matching its bold/quote signature); others keep nil for the default
    /// yellow wash.
    public var markBackgroundHex: String? {
        switch self {
        case .colaElegant, .elegantPlus: return "rgba(196, 75, 43, 0.15)"
        default: return nil
        }
    }

    /// Hairline border hex (headings' underline, ColaMD's `--border-color`).
    public var borderColorHex: String? {
        switch self {
        case .colaLight: return "#d0d7de"
        case .colaDark: return "#30363d"
        case .colaElegant: return "#d8d3ce"
        case .colaNewsprint: return "#d4d0c8"
        case .elegantPlus: return "#d8d3ce"
        case .system: return nil
        }
    }

    /// GitHub-style table zebra row background hex.
    public var tableZebraHex: String? {
        switch self {
        case .system: return nil
        case .colaLight: return "#f6f8fa"
        case .colaDark: return "#161b22"
        case .colaElegant: return "#eae6e1"
        case .colaNewsprint: return "#eae6de"
        case .elegantPlus: return "#eae6e1"
        }
    }

    /// Preferred body font family for this preset, or nil to keep the user's.
    /// Both faces ship with macOS (Songti SC is the system Chinese serif;
    /// Georgia is a system Latin serif), so they resolve without extra fonts.
    public var fontName: String? {
        switch self {
        case .colaElegant, .elegantPlus: return "Songti SC"
        case .colaNewsprint: return "Georgia"
        default: return nil
        }
    }
}
