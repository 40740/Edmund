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

    @Test("ColaMD blockquote carries the 4px terracotta bar and spec padding")
    func colaBlockquote() {
        let css = HTMLTheme.css(theme(.colaElegant), callouts: Callout.defaultStyles, dark: false)
        #expect(css.contains("border-left: 4px solid var(--cola-accent);"))
        // Spec §4.5: padding 16px 22px 16px 26px (上下对称16px)
        #expect(css.contains("padding: 16px 22px 16px 26px;"))
        // Spec §4.5: border-radius 0 6px 6px 0
        #expect(css.contains("border-radius: 0 6px 6px 0;"))
        // Spec §4.5: hover border-left-width 4px→5px
        #expect(css.contains("blockquote:hover { border-left-width: 5px; }"))
        #expect(css.contains("blockquote > p:first-child { margin-top: 0; }"))
        #expect(css.contains("blockquote > p:last-child  { margin-bottom: 0; }"))
    }

    @Test("ColaMD code block uses the dark panel with spec padding 20px 24px")
    func colaCodeBlock() {
        let css = HTMLTheme.css(theme(.colaElegant), callouts: Callout.defaultStyles, dark: false)
        // Spec §4.2: padding 20px 24px, border-radius 8px, line-height 1.65
        #expect(css.contains("padding: 20px 24px;"))
        #expect(css.contains("background: var(--cola-code-bg);"))
        #expect(css.contains("border-radius: 8px;"))
        #expect(css.contains("line-height: 1.65;"))
    }

    @Test("ColaMD inline code is a terracotta chip with spec padding 3px 8px")
    func colaInlineCode() {
        let css = HTMLTheme.css(theme(.colaElegant), callouts: Callout.defaultStyles, dark: false)
        // Spec §4.3: padding 3px 8px, border-radius 4px
        #expect(css.contains("padding: 3px 8px;"))
        #expect(css.contains("background: var(--cola-inline-code-bg);"))
        #expect(css.contains("color: var(--cola-accent);"))
        #expect(css.contains("border-radius: 4px;"))
    }

    @Test("ColaMD table has outer border, terracotta header underline, and zebra striping")
    func colaTable() {
        let css = HTMLTheme.css(theme(.colaElegant), callouts: Callout.defaultStyles, dark: false)
        // Spec §4.6: container border 1px solid #d8d3ce + border-radius 8px
        #expect(css.contains("border: 1px solid var(--cola-border); border-radius: 8px;"))
        // Spec §4.6: header border-bottom 2px solid #c44b2b
        #expect(css.contains("border-bottom: 2px solid var(--cola-accent);"))
        // Spec §4.6: header padding 12px 16px
        #expect(css.contains("padding: 12px 16px;"))
        // Spec §4.6: cell padding 11px 16px
        #expect(css.contains("padding: 11px 16px;"))
        // Spec §4.6: zebra striping tr:nth-child(even)
        #expect(css.contains("tr:nth-child(even)"))
    }

    @Test("ColaMD h1/h2 have underline per spec §4.1")
    func colaHeadingUnderline() {
        let css = HTMLTheme.css(theme(.colaElegant), callouts: Callout.defaultStyles, dark: false)
        // Spec §4.1: h1/h2 带下划线
        #expect(css.contains("h1 { font-size: 1.8em; padding-bottom: 0.3em; border-bottom: 1px solid var(--cola-border); }"))
        #expect(css.contains("h2 { font-size: 1.5em; padding-bottom: 0.2em; border-bottom: 1px solid var(--cola-border); }"))
    }

    @Test("ColaMD hr has the gradient hairline with centered terracotta dot")
    func colaHR() {
        let css = HTMLTheme.css(theme(.colaElegant), callouts: Callout.defaultStyles, dark: false)
        // Spec §4.7: gradient transparent→#d8d3ce 20%→80%→transparent
        #expect(css.contains("linear-gradient(to right,"))
        // Spec §4.7: center 6px dot #c44b2b 50%透明
        #expect(css.contains("hr::after"))
        #expect(css.contains("width: 6px; height: 6px;"))
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
