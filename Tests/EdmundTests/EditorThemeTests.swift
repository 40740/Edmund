import Testing
import AppKit
@testable import EdmundCore

@Suite("EditorTheme — Math colors")
struct EditorThemeMathColorTests {

    @Test("Default math colors are red (operators) and orange (numbers)")
    @MainActor func defaults() {
        let t = EditorTheme.default
        #expect(t.mathOperatorHex == "#D70015")
        #expect(t.mathNumberHex == "#C77800")
        #expect(t.mathOperatorColor == NSColor(hex: "#D70015"))
        #expect(t.mathNumberColor == NSColor(hex: "#C77800"))
    }

    @Test("Custom math hex resolves to the matching color")
    @MainActor func customHex() {
        let t = EditorTheme(fontName: "Helvetica", fontSize: 14,
                            linkBlueHex: "#000000", codeHex: "#000000",
                            lineSpacing: 0, paragraphSpacingBefore: 0,
                            mathOperatorHex: "#112233", mathNumberHex: "#445566")
        #expect(t.mathOperatorColor == NSColor(hex: "#112233"))
        #expect(t.mathNumberColor == NSColor(hex: "#445566"))
    }

    @Test("An invalid hex falls back to a system color, not a crash")
    @MainActor func invalidHexFallback() {
        let t = EditorTheme(fontName: "Helvetica", fontSize: 14,
                            linkBlueHex: "#000000", codeHex: "#000000",
                            lineSpacing: 0, paragraphSpacingBefore: 0,
                            mathOperatorHex: "nonsense", mathNumberHex: "")
        #expect(t.mathOperatorColor == NSColor.systemRed)
        #expect(t.mathNumberColor == NSColor.systemOrange)
    }
}


@Suite("ColaMD preset palette")
struct ColaThemePresetPaletteTests {

    @Test("Light and dark presets provide complete page/code palettes")
    func lightDarkPalettes() {
        #expect(ColaThemePreset.colaLight.backgroundColorHex != nil)
        #expect(ColaThemePreset.colaLight.textColorHex != nil)
        #expect(ColaThemePreset.colaLight.codeBlockBackgroundHex != nil)

        #expect(ColaThemePreset.colaDark.backgroundColorHex != nil)
        #expect(ColaThemePreset.colaDark.textColorHex != nil)
        #expect(ColaThemePreset.colaDark.codeBlockBackgroundHex != nil)
    }

    @Test("Elegant uses a dark fenced-code panel with light code ink")
    func elegantCodePalette() {
        #expect(ColaThemePreset.colaElegant.codeBlockBackgroundHex == "#2c2c2c")
        #expect(ColaThemePreset.colaElegant.codeBlockTextHex == "#e0dcd7")
        #expect(ColaThemePreset.colaElegant.quoteBackgroundHex == "#eae6e1")
    }
}
