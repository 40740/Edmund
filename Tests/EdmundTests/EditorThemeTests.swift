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

@Suite("EditorTheme — preset font vs. custom font")
struct EditorThemeFontPresetTests {

    @Test("A ColaMD preset's serif face wins until the user customizes the font")
    @MainActor func presetFontDefaults() {
        let t = EditorTheme(fontName: "Helvetica", fontSize: 16,
                            linkBlueHex: "#000", codeHex: "#000",
                            lineSpacing: 0, paragraphSpacingBefore: 0,
                            preset: .colaElegant)
        // Elegant prescribes Songti SC; the user hasn't overridden it.
        #expect(t.bodyFont.familyName == "Songti SC")
    }

    @Test("A user-chosen font wins over the preset's face once customized")
    @MainActor func customFontWins() {
        let t = EditorTheme(fontName: "Helvetica", fontSize: 16,
                            linkBlueHex: "#000", codeHex: "#000",
                            lineSpacing: 0, paragraphSpacingBefore: 0,
                            preset: .colaElegant,
                            customFontOverridesPreset: true)
        #expect(t.bodyFont.familyName == "Helvetica")
    }

    @Test("A preset without a font face always uses the user's font")
    @MainActor func presetWithoutFontUsesUserFont() {
        let t = EditorTheme(fontName: "Helvetica", fontSize: 16,
                            linkBlueHex: "#000", codeHex: "#000",
                            lineSpacing: 0, paragraphSpacingBefore: 0,
                            preset: .colaDark)  // colaDark has no fontName
        #expect(t.bodyFont.familyName == "Helvetica")
    }
}
