// FontSettings — owns the editor fonts, line height, and accent hex, bridges the
// AppKit font panel, and applies changes to every open document.

import SwiftUI
import AppKit
import EdmundCore

// MARK: - Font / theme state

/// Owns the editor's standard/monospace fonts and line height, bridges the
/// AppKit font panel, and applies font/line-height changes to open documents
/// (the genuinely AppKit-bound part of the Appearance pane).
@MainActor
final class FontSettings: NSObject, ObservableObject {
    @Published var standardFont: NSFont
    @Published var monospaceFont: NSFont
    @Published var lineHeight: CGFloat
    @Published var standardLigatures: Bool { didSet { applyLigatures() } }
    @Published var monospaceLigatures: Bool { didSet { applyLigatures() } }
    /// A single editor-wide antialias setting (both font toggles share it).
    @Published var antialias: Bool { didSet { applyAntialias() } }
    /// The active theme preset. The Appearance pane writes to this via
    /// `applyPreset(_:)` (which seeds the editor theme + refreshes documents);
    /// no `didSet` here so `applyPreset` can mutate it without recursing.
    @Published var themePreset: ThemePreset

    private var theme: EditorTheme
    /// True while `applyPreset` is mutating the @Published fields — suppresses
    /// the per-field `applyLigatures` / `applyAntialias` side effects so they
    /// don't fight the preset's wholesale `applyToDocuments` at the end.
    private var isApplyingPreset = false
    private enum Target { case standard, monospace }
    private var target: Target = .standard

    override init() {
        let loaded = EditorTheme.load()
        // Sync the two preset stores on startup. The Appearance pane writes
        // `AppSettings.themePreset` (a settings key for @AppStorage); the
        // EditorTheme itself carries `preset` (an Editor* UserDefaults key).
        // They can drift if a previous version wrote one but not the other;
        // pick `AppSettings.themePreset` as the source of truth on launch and
        // stamp it back onto the theme so the rest of init sees one value.
        let startupPreset = AppSettings.themePreset
        var theme = loaded
        if theme.preset != startupPreset {
            theme.preset = startupPreset
            theme.save()
        }
        self.theme = theme
        standardFont = theme.bodyFont
        monospaceFont = theme.monospaceFont()
        standardLigatures = theme.standardLigatures
        monospaceLigatures = theme.monospaceLigatures
        antialias = theme.antialias
        themePreset = theme.preset
        let size = theme.bodyFont.pointSize
        lineHeight = size > 0 ? max(1, min(3, (size + theme.lineSpacing) / size)) : 1
        super.init()
    }

    var standardSummary: String { Self.summary(standardFont) }
    var monospaceSummary: String { Self.summary(monospaceFont) }

    func selectStandardFont() { beginFontPanel(.standard, current: standardFont) }
    func selectMonospaceFont() { beginFontPanel(.monospace, current: monospaceFont) }

    func setStandardSize(_ size: CGFloat) {
        standardFont = NSFont(descriptor: standardFont.fontDescriptor, size: size) ?? standardFont
        applyTheme()
    }

    func setMonospaceSize(_ size: CGFloat) {
        monospaceFont = NSFont(descriptor: monospaceFont.fontDescriptor, size: size) ?? monospaceFont
        applyMonospace()
    }

    func setLineHeight(_ value: CGFloat) {
        lineHeight = max(1, min(3, value))
        applyTheme()
    }

    /// Stamps `preset`'s signature defaults onto the editor theme and refreshes
    /// every open document + Read view. Called when the user picks a new theme
    /// in the Appearance pane. The preset's font/accent/line-spacing values
    /// replace whatever was there; size and ligatures come along for the ride.
    /// After this fires, the user is free to tweak any individual field via the
    /// font pickers / line-height stepper — those edits write through
    /// `applyTheme` and persist on top of the preset.
    func applyPreset(_ preset: ThemePreset) {
        // Persist the preset choice first so a crash between here and the
        // document refresh can't leave the UI showing one preset while
        // `EditorTheme.load()` would return another.
        AppSettings.themePreset = preset
        // Suppress the per-field didSet side effects while we reseed — the
        // single `applyToDocuments(merged)` at the end is the canonical
        // refresh; intermediate `applyLigatures` calls would read stale `theme`
        // state and clobber the preset.
        isApplyingPreset = true
        defer { isApplyingPreset = false }

        let seed: EditorTheme
        switch preset {
        case .edmund:        seed = .default
        case .colaElegant:   seed = .colaElegant
        }

        // Carry over the live size + ligature toggles so a preset switch
        // doesn't yank the user's font-size preference back to 16pt. Everything
        // else (font family, accent, code color, line spacing, math colors,
        // mono family/size) comes from the preset.
        var merged = seed
        merged.fontSize = max(8, min(72, theme.fontSize))
        merged.monospaceFontSize = max(8, min(72, theme.monospaceFontSize))
        merged.standardLigatures = theme.standardLigatures
        merged.monospaceLigatures = theme.monospaceLigatures
        merged.antialias = theme.antialias
        merged.preset = preset

        // Refresh @Published state so the font rows and stepper update.
        standardFont = merged.bodyFont
        monospaceFont = merged.monospaceFont()
        standardLigatures = merged.standardLigatures
        monospaceLigatures = merged.monospaceLigatures
        antialias = merged.antialias
        themePreset = preset
        let size = merged.bodyFont.pointSize
        lineHeight = size > 0 ? max(1, min(3, (size + merged.lineSpacing) / size)) : 1

        theme = merged
        merged.save()
        applyToDocuments(merged)
    }

    @objc func changeFont(_ sender: NSFontManager) {
        switch target {
        case .standard:
            standardFont = sender.convert(standardFont)
            applyTheme()
        case .monospace:
            monospaceFont = sender.convert(monospaceFont)
            applyMonospace()
        }
    }

    private func beginFontPanel(_ target: Target, current: NSFont) {
        self.target = target
        let manager = NSFontManager.shared
        manager.target = self
        manager.action = #selector(changeFont(_:))
        manager.setSelectedFont(current, isMultiple: false)
        manager.orderFrontFontPanel(nil)
    }

    private func applyMonospace() {
        var updated = theme
        updated.monospaceFontName = monospaceFont.fontName
        updated.monospaceFontSize = monospaceFont.pointSize
        theme = updated
        updated.save()
        applyToDocuments(updated)
    }

    private func applyLigatures() {
        guard !isApplyingPreset else { return }
        var updated = theme
        updated.standardLigatures = standardLigatures
        updated.monospaceLigatures = monospaceLigatures
        theme = updated
        updated.save()
        applyToDocuments(updated)
    }

    private func applyAntialias() {
        guard !isApplyingPreset else { return }
        var updated = theme
        updated.antialias = antialias
        theme = updated
        updated.save()
        applyToDocuments(updated)
    }

    private func applyTheme() {
        var updated = theme
        updated.fontName = standardFont.fontName
        updated.fontSize = standardFont.pointSize
        updated.lineSpacing = max(0, (lineHeight - 1) * standardFont.pointSize)
        theme = updated
        updated.save()
        applyToDocuments(updated)
    }

    /// Apply a named preset (Edmund or ColaMD) to the whole app. Stamps the
    /// preset's seed values onto `EditorTheme` (font, accent, spacing, …) and
    /// pushes it to every open document.
    func applyPreset(_ preset: ThemePreset) {
        let seed: EditorTheme = preset == .colaElegant ? .colaElegant : .default
        // Adopt the preset's font/line-height values too, so the picker rows
        // and the editable font fields stay consistent.
        standardFont = seed.bodyFont
        monospaceFont = seed.monospaceFont()
        standardLigatures = seed.standardLigatures
        monospaceLigatures = seed.monospaceLigatures
        antialias = seed.antialias
        let size = seed.bodyFont.pointSize
        lineHeight = size > 0 ? max(1, min(3, (size + seed.lineSpacing) / size)) : 1

        theme = seed
        seed.save()
        applyToDocuments(seed)
    }

    /// The currently-selected preset (for the settings picker).
    var currentPreset: ThemePreset { theme.preset }

    private func applyToDocuments(_ theme: EditorTheme) {
        for case let document as Document in NSDocumentController.shared.documents {
            document.editor?.applyTheme(theme)
            // Reflect the theme change live in an open Read view too.
            document.refreshReadView()
        }
    }

    private static func summary(_ font: NSFont) -> String {
        let name = font.displayName ?? font.familyName ?? font.fontName
        return "\(name)  \(Int(round(font.pointSize)))"
    }
}
