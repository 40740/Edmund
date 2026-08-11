import AppKit

// MARK: - ThemePreset
//
// A *named, opinionated* look for the editor and the Read/PDF rendering — the
// "pick a theme" knob on top of the always-customizable `EditorTheme` (font,
// size, line spacing, accent hex). Selecting a preset stamps its defaults onto
// `EditorTheme`, after which the user is free to tweak any field (the preset
// only seeds values; nothing forces them to stay).
//
// Today two presets ship:
//
// - `.edmund` — the original Edmund look (Iowan Old Style serif body, blue
//   accent, white/near-black page). The historical default, kept byte-for-byte.
// - `.colaElegant` — "ColaMD Elegant": warm-paper background (#f0edea),
//   terracotta accent (#c44b2b), serif body with generous 0.04em tracking and
//   1.9 line-height, One-Dark code panel. Ported from
//   https://github.com/marswaveai/ColaMD (`themes/elegant.css`).
//
// Routing: `HTMLTheme.css(theme:…)` reads `theme.preset` and dispatches to the
// matching CSS builder. `EditorTextView.editorBackgroundColor` does the same so
// the Edit-mode surface matches the Read-mode page. Anything that only consumes
// `EditorTheme` fields (fonts, accent hex, code hex, line spacing) needs no
// preset awareness — those values are already preset-stamped at the source.
public enum ThemePreset: String, CaseIterable, Sendable, Identifiable {
    case edmund
    case colaElegant

    /// `Identifiable` conformance so the Appearance pane can iterate the
    /// presets with `ForEach(ThemePreset.displayOrder)`. The raw value is a
    /// stable id across launches (it's also the UserDefaults payload).
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .edmund:        return "Edmund"
        case .colaElegant:   return "ColaMD"
        }
    }

    /// Short subtitle for the picker row.
    public var subtitle: String {
        switch self {
        case .edmund:        return "经典 — 白底蓝字衬线体"
        case .colaElegant:   return "暖纸底色、赤陶强调色、衬线正文"
        }
    }

    /// Display order in the Appearance pane (top to bottom).
    public static let displayOrder: [ThemePreset] = [.edmund, .colaElegant]
}
