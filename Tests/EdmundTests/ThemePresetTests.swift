import Testing
import AppKit
@testable import EdmundCore

// MARK: - ThemePreset + ColaMD Elegant routing
//
// Verifies that selecting `.colaElegant` produces the warm-paper, terracotta
// stylesheet documented in `UI-设计文档.md`, and that `.edmund` (the historical
// default) is unchanged — a regression guard against accidental coupling
// between the two CSS builders.
@Suite("ThemePreset — ColaMD Elegant CSS")
@MainActor
struct ThemePresetTests {

    /// A minimal theme carrying each preset — same font/size/spacing so any
    /// difference in the emitted CSS is purely the preset's fault.
    private func theme(_ preset: ThemePreset) -> EditorTheme {
        EditorTheme(fontName: "Helvetica", fontSize: 16,
                    linkBlueHex: "#3366E6", codeHex: "#8A2425",
                    lineSpacing: 4, paragraphSpacingBefore: 2,
                    preset: preset)
    }

    // MARK: Preset routing

    @Test("Default theme carries the .edmund preset")
    func defaultPreset() {
        #expect(EditorTheme.default.preset == .edmund)
        // An uninitialized EditorTheme.load() also reads back .edmund. Use a
        // throwaway suite so this test can't pollute .standard for other tests.
        let suite = UserDefaults(suiteName: "cola-preset-default-test")!
        defer { suite.removePersistentDomain(forName: "cola-preset-default-test") }
        suite.removeObject(forKey: "EditorThemePreset")
        #expect(EditorTheme.load(from: suite).preset == .edmund)
    }

    @Test("ColaMD preset persists round-trip through UserDefaults")
    func presetRoundTrip() {
        let defaults = UserDefaults(suiteName: "cola-preset-roundtrip-test")!
        defer { defaults.removePersistentDomain(forName: "cola-preset-roundtrip-test") }

        var t = EditorTheme.colaElegant
        t.save(to: defaults)
        let loaded = EditorTheme.load(from: defaults)
        #expect(loaded.preset == .colaElegant)
        // Signature ColaMD values survived the round-trip.
        #expect(loaded.linkBlueHex == "#C44B2B")
        #expect(loaded.codeHex == "#C44B2B")
    }

    // MARK: ColaMD CSS — light mode

    @Test("ColaMD light mode emits the warm-paper palette tokens")
    func colaLightPalette() {
        let css = HTMLTheme.css(theme(.colaElegant), callouts: Callout.defaultStyles, dark: false)
        // The spec's signature tokens (UI-设计文档.md §2.1).
        #expect(css.contains("--cola-bg: #f0edea;"))
        #expect(css.contains("--cola-bg-soft: #eae6e1;"))
        #expect(css.contains("--cola-text: #2c2c2c;"))
        #expect(css.contains("--cola-text-soft: #555555;"))
        #expect(css.contains("--cola-accent: #c44b2b;"))
        #expect(css.contains("--cola-accent-soft: rgba(196, 75, 43, 0.15);"))
        #expect(css.contains("--cola-border: #d8d3ce;"))
        #expect(css.contains("--cola-code-bg: #2c2c2c;"))
        #expect(css.contains("--cola-code-text: #e0dcd7;"))
        #expect(css.contains("--cola-inline-code-bg: #e8e4df;"))
        #expect(css.contains("--cola-heading: #1a1a1a;"))
    }

    @Test("ColaMD light mode body uses 0.04em letter-spacing and justified paragraphs")
    func colaLightTypography() {
        let css = HTMLTheme.css(theme(.colaElegant), callouts: Callout.defaultStyles, dark: false)
        #expect(css.contains("letter-spacing: 0.04em;"))
        #expect(css.contains("text-align: justify;"))
        // Headings sit a touch tighter.
        #expect(css.contains("letter-spacing: 0.02em;"))
    }

    @Test("ColaMD blockquote carries the 4px terracotta bar and symmetric 16px pads")
    func colaBlockquote() {
        let css = HTMLTheme.css(theme(.colaElegant), callouts: Callout.defaultStyles, dark: false)
        #expect(css.contains("border-left: 4px solid var(--cola-accent);"))
        #expect(css.contains("padding: 16px 22px 16px 26px;"))
        // First/last child margins collapse so the pads read as symmetric.
        #expect(css.contains("blockquote > p:first-child { margin-top: 0; }"))
        #expect(css.contains("blockquote > p:last-child  { margin-bottom: 0; }"))
    }

    @Test("ColaMD code block uses the dark panel with 20/24 breathing room")
    func colaCodeBlock() {
        let css = HTMLTheme.css(theme(.colaElegant), callouts: Callout.defaultStyles, dark: false)
        #expect(css.contains("padding: 20px 24px;"))
        #expect(css.contains("background: var(--cola-code-bg);"))
        // 8px radius per spec §4.2.
        #expect(css.contains("border-radius: 8px;"))
    }

    @Test("ColaMD inline code is a terracotta chip with 3/8 padding")
    func colaInlineCode() {
        let css = HTMLTheme.css(theme(.colaElegant), callouts: Callout.defaultStyles, dark: false)
        #expect(css.contains("padding: 3px 8px;"))
        #expect(css.contains("background: var(--cola-inline-code-bg);"))
        #expect(css.contains("color: var(--cola-accent);"))
    }

    @Test("ColaMD table header carries the 2px terracotta underline")
    func colaTable() {
        let css = HTMLTheme.css(theme(.colaElegant), callouts: Callout.defaultStyles, dark: false)
        #expect(css.contains("border-bottom: 2px solid var(--cola-accent);"))
        // Zebra striping.
        #expect(css.contains("tr:nth-child(even)"))
    }

    @Test("ColaMD mark uses the terracotta tint, not default yellow")
    func colaMark() {
        let css = HTMLTheme.css(theme(.colaElegant), callouts: Callout.defaultStyles, dark: false)
        #expect(css.contains("background: var(--cola-accent-soft);"))
    }

    @Test("ColaMD hr has the centered terracotta dot")
    func colaHR() {
        let css = HTMLTheme.css(theme(.colaElegant), callouts: Callout.defaultStyles, dark: false)
        #expect(css.contains("hr::after"))
        #expect(css.contains("border-radius: 50%;"))
    }

    // MARK: ColaMD CSS — dark mode

    @Test("ColaMD dark mode lifts the terracotta and warms the page")
    func colaDarkPalette() {
        let css = HTMLTheme.css(theme(.colaElegant), callouts: Callout.defaultStyles, dark: true)
        // The signature dark-mode tokens (UI-设计文档.md §2.2).
        #expect(css.contains("--cola-bg: #1c1a18;"))
        #expect(css.contains("--cola-bg-soft: #26231f;"))
        #expect(css.contains("--cola-text: #d8d3ce;"))
        #expect(css.contains("--cola-text-soft: #a89f96;"))
        #expect(css.contains("--cola-accent: #e0653f;"))
        #expect(css.contains("--cola-accent-soft: rgba(224, 101, 63, 0.18);"))
        #expect(css.contains("--cola-border: #3a342e;"))
        #expect(css.contains("--cola-code-bg: #14110f;"))
        #expect(css.contains("--cola-inline-code-bg: #2a2622;"))
        #expect(css.contains("--cola-heading: #e0dcd7;"))
    }

    // MARK: One-Dark code palette

    @Test("ColaMD emits the One-Dark syntax palette for code blocks")
    func colaCodeTokens() {
        let css = HTMLTheme.css(theme(.colaElegant), callouts: Callout.defaultStyles, dark: false)
        // One-Dark hexes from UI-设计文档.md §5.
        #expect(css.contains("pre code .tok-keyword { color: #c678dd; }"))
        #expect(css.contains("pre code .tok-string { color: #98c379; }"))
        #expect(css.contains("pre code .tok-number { color: #d19a66; }"))
        #expect(css.contains("pre code .tok-comment { color: #7c7873; }"))
    }

    // MARK: Background hex routing

    @Test("HTMLTheme.backgroundColor resolves to warm paper for ColaMD light")
    func backgroundColorRouting() {
        let light = HTMLTheme.backgroundColor(dark: false, preset: .colaElegant)
        #expect(light.hexString == "#F0EDEA")
        let dark = HTMLTheme.backgroundColor(dark: true, preset: .colaElegant)
        #expect(dark.hexString == "#1C1A18")
        // Edmund preset unchanged.
        #expect(HTMLTheme.backgroundColor(dark: false, preset: .edmund).hexString == "#FFFFFF")
        #expect(HTMLTheme.backgroundColor(dark: true, preset: .edmund).hexString == "#292929")
    }

    // MARK: Edmund preset regression

    @Test("Edmund preset CSS is unchanged — no ColaMD tokens leak in")
    func edmundUntouched() {
        let css = HTMLTheme.css(theme(.edmund), callouts: Callout.defaultStyles, dark: false)
        // The ColaMD tokens must NOT appear in the Edmund path.
        #expect(!css.contains("--cola-bg:"))
        #expect(!css.contains("--cola-accent:"))
        // The Edmund CSS vars are still emitted.
        #expect(css.contains("--bg: #ffffff;"))
        #expect(css.contains("--fg:"))
        #expect(css.contains("--accent: #3366E6;"))
    }

    @Test("Edmund preset dark mode still uses #292929 page background")
    func edmundDarkUntouched() {
        let css = HTMLTheme.css(theme(.edmund), callouts: Callout.defaultStyles, dark: true)
        #expect(css.contains("--bg: #292929;"))
        #expect(!css.contains("--cola-bg:"))
    }
}
