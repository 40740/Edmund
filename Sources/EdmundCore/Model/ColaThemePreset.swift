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

    public var id: String { rawValue }

    /// Display name shown in the Settings ▸ Appearance picker.
    public var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .colaLight: return "ColaMD 浅色"
        case .colaDark: return "ColaMD 深色"
        case .colaElegant: return "ColaMD 优雅"
        case .colaNewsprint: return "ColaMD 新闻纸"
        }
    }

    /// Whether this preset forces a dark appearance (`.system` is nil).
    public var forcedDark: Bool? {
        switch self {
        case .system: return nil
        case .colaDark: return true
        case .colaLight, .colaElegant, .colaNewsprint: return false
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
        }
    }

    /// Inline-code ink hex (overrides the theme's `codeHex`).
    public var codeColorHex: String? {
        switch self {
        case .system: return nil
        case .colaLight: return "#cf222e"
        case .colaDark: return "#ff7b72"
        case .colaElegant: return "#c44b2b"
        case .colaNewsprint: return "#7a3e9d"
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
        }
    }

    /// Preferred body font family for this preset, or nil to keep the user's.
    /// Both faces ship with macOS (Songti SC is the system Chinese serif;
    /// Georgia is a system Latin serif), so they resolve without extra fonts.
    public var fontName: String? {
        switch self {
        case .colaElegant: return "Songti SC"
        case .colaNewsprint: return "Georgia"
        default: return nil
        }
    }
}
