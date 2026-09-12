import AppKit
import EdmundMarkdown

// MARK: - EditorTheme (AppKit)
//
// The AppKit-facing half of `EditorTheme`: it resolves the stored values into
// `NSFont` / `NSColor`. The stored model itself lives in `EdmundMarkdown`, which
// has no AppKit dependency.
//
// This belongs to the *rendering* layer rather than the editor: `HTMLTheme`
// resolves the same NSColors into the page's CSS and `DocumentHTML` tints the
// math bitmaps with `bodyTextColorResolved(dark:)`, so the editor and Read mode
// keep one definition of the ink. `EdmundCore` imports it like any other part of
// its rendering pipeline.
extension EditorTheme {


    @MainActor public var bodyFont: NSFont {
        // A ColaMD preset's serif face is the default while active, but once the
        // user picks their own body font it wins (see `customFontOverridesPreset`)
        // — otherwise changing the font in the Appearance pane would silently
        // no-op while an Elegant / Newsprint preset is on, and switching presets
        // would snap the type back to the theme's face. A preset with no face
        // (Light / Dark / System) always uses the user's choice.
        let resolvedName = (customFontOverridesPreset || preset.fontName == nil)
            ? fontName
            : preset.fontName!
        let base = NSFont(name: resolvedName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        return Self.applyingLigatures(standardLigatures, to: base)
    }

    /// The monospaced font, at `size` (default: the theme's monospace size).
    /// Falls back to the system monospaced font when no family is set or it can't
    /// be loaded.
    @MainActor public func monospaceFont(ofSize size: CGFloat? = nil) -> NSFont {
        let resolved = size ?? monospaceFontSize
        let base: NSFont = {
            if !monospaceFontName.isEmpty, let font = NSFont(name: monospaceFontName, size: resolved) {
                return font
            }
            // Default when no family is chosen: Input Mono Narrow, then Input Mono,
            // then the system monospaced font — all Regular.
            for name in ["InputMonoNarrow-Regular", "InputMono-Regular"] {
                if let font = NSFont(name: name, size: resolved) { return font }
            }
            return .monospacedSystemFont(ofSize: resolved, weight: .regular)
        }()
        return Self.applyingLigatures(monospaceLigatures, to: base)
    }

    /// Returns `font` with ligatures disabled (when `on` is false) by turning off
    /// both common ligatures and contextual alternates in its descriptor — the
    /// latter is what drives programming ligatures like Fira Code's `=>`/`==`.
    /// Baking it into the font (rather than the `.ligature` attribute) is what the
    /// editor's TextKit 2 pipeline reliably honors.
    private static func applyingLigatures(_ on: Bool, to font: NSFont) -> NSFont {
        guard !on else { return font }
        let kContextualAlternatesType = 36
        let kContextualAlternatesOffSelector = 1
        let settings: [[NSFontDescriptor.FeatureKey: Int]] = [
            [.typeIdentifier: kLigaturesType, .selectorIdentifier: kCommonLigaturesOffSelector],
            [.typeIdentifier: kContextualAlternatesType, .selectorIdentifier: kContextualAlternatesOffSelector],
        ]
        let descriptor = font.fontDescriptor.addingAttributes([.featureSettings: settings])
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }

    /// Body-text ink — **the** definition, read by both Edit mode
    /// (`EditorTextView.foregroundColor`) and Read mode (`HTMLTheme`'s `--fg`,
    /// and the math bitmaps `DocumentHTML` embeds). It lives here because the two
    /// modes had drifted: Edit mode painted the system `textColor` while Read
    /// mode hard-coded `#1a1a1a`, so in light mode the identical equation was
    /// pure black in one mode and 10% lighter in the other (measured off
    /// screenshots: peak ink coverage 1.000 vs 0.863).
    ///
    /// Light mode keeps the system color: Edit mode is a real `NSTextView`, and
    /// `textColor` is what every native text surface paints — it also tracks
    /// Increase Contrast, which a hex cannot. On white the difference from
    /// `#1a1a1a` is perceptually tiny (21:1 vs 18.9:1 contrast), so matching the
    /// system costs nothing. Dark mode is the exception, and it predates this:
    /// `textColor` is pure white there, which glares against the `#292929` page,
    /// so both modes use Read mode's long-standing `#e6e6e6` instead.
    @MainActor public static func bodyTextColor(dark: Bool) -> NSColor {
        dark ? NSColor(srgbRed: 230 / 255, green: 230 / 255, blue: 230 / 255, alpha: 1)
             : .textColor
    }

    /// `bodyTextColor(dark:)` resolved against that appearance rather than
    /// whichever one happens to be current. Read mode needs this: its CSS and its
    /// math bitmaps are generated for an explicit light/dark target (an export, or
    /// a preview while the app sits in the other appearance), and a dynamic
    /// `textColor` resolved at the wrong moment would bake in the wrong ink.
    @MainActor public static func bodyTextColorResolved(dark: Bool) -> NSColor {
        var color = bodyTextColor(dark: dark)
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            color = color.usingColorSpace(.deviceRGB) ?? color
        }
        return color
    }

    @MainActor public var linkBlueColor: NSColor {
        if let hex = preset.linkColorHex { return NSColor(hex: hex) ?? .systemBlue }
        return NSColor(hex: linkBlueHex) ?? .systemBlue
    }

    @MainActor public var codeColor: NSColor {
        if let hex = preset.codeColorHex { return NSColor(hex: hex) ?? .systemRed }
        return NSColor(hex: codeHex) ?? .systemRed
    }

    @MainActor public var mathOperatorColor: NSColor {
        NSColor(hex: mathOperatorHex) ?? .systemRed
    }

    // MARK: ColaMD preset accent colors

    /// Bold-text ink for a ColaMD preset, or nil to keep the body color.
    @MainActor public var strongColor: NSColor? {
        preset.strongColorHex.flatMap { NSColor(hex: $0) }
    }

    /// Blockquote left-bar color for a ColaMD preset, or nil for the default.
    @MainActor public var quoteBarColor: NSColor? {
        preset.quoteBarHex.flatMap { NSColor(hex: $0) }
    }

    /// Blockquote background fill for a ColaMD preset, or nil for none.
    @MainActor public var quoteBackgroundColor: NSColor? {
        preset.quoteBackgroundHex.flatMap { NSColor(hex: $0) }
    }

    /// Blockquote text color for a ColaMD preset, or nil for the default.
    @MainActor public var quoteTextColor: NSColor? {
        preset.quoteTextHex.flatMap { NSColor(hex: $0) }
    }

    /// Table header bottom-rule accent for a ColaMD preset, or nil for default.
    @MainActor public var tableHeadAccentColor: NSColor? {
        preset.tableHeadAccentHex.flatMap { NSColor(hex: $0) }
    }

    /// Fenced code block background for a ColaMD preset, or nil for default.
    @MainActor public var codeBlockBackgroundColor: NSColor? {
        preset.codeBlockBackgroundHex.flatMap { NSColor(hex: $0) }
    }

    /// Fenced code block text for a ColaMD preset, or nil for default.
    @MainActor public var codeBlockTextColor: NSColor? {
        preset.codeBlockTextHex.flatMap { NSColor(hex: $0) }
    }

    /// Inline-code chip background for a ColaMD preset, or nil for default.
    @MainActor public var inlineCodeBackgroundColor: NSColor? {
        preset.inlineCodeBackgroundHex.flatMap { NSColor(hex: $0) }
    }

    /// Hairline border color for a ColaMD preset (headings' underline), or nil.
    @MainActor public var borderColor: NSColor? {
        preset.borderColorHex.flatMap { NSColor(hex: $0) }
    }

    @MainActor public var mathNumberColor: NSColor {
        NSColor(hex: mathNumberHex) ?? .systemOrange
    }
}
