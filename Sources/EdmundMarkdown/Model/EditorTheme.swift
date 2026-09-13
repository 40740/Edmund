import Foundation

/// All user-configurable visual settings for the editor.
///
/// Stored as simple types (String, CGFloat) so it serializes cleanly to
/// UserDefaults. The AppKit-facing halves — the `NSFont` / `NSColor`
/// equivalents the editor renders from — live in `EdmundCore` as an extension,
/// because they are the only part of this type that needs a framework the
/// preview doesn't (the preview consumes the hex strings as CSS).
public struct EditorTheme: Equatable, Sendable {

    // MARK: - Font

    public var fontName: String
    public var fontSize: CGFloat

    /// Monospaced font for code (inline, blocks, tables). An empty name means the
    /// system monospaced font.
    public var monospaceFontName: String
    public var monospaceFontSize: CGFloat

    /// Whether ligatures are enabled for the standard (body) and monospaced fonts.
    public var standardLigatures: Bool
    public var monospaceLigatures: Bool

    /// Whether editor text is antialiased (a single editor-wide setting).
    public var antialias: Bool

    // MARK: - Colors (hex strings, e.g. "#3366E6")

    public var linkBlueHex: String
    public var codeHex: String
    /// Color for LaTeX operators/commands (`_`, `^`, `\sum`, …) in raw math.
    public var mathOperatorHex: String
    /// Color for numbers in raw math.
    public var mathNumberHex: String

    // MARK: - Spacing

    public var lineSpacing: CGFloat
    public var paragraphSpacingBefore: CGFloat

    /// ColaMD theme preset layered on top of these settings (System = off). The
    /// preset overrides the derived background/ink/font/link/code values without
    /// touching the stored font/colour fields, so switching back to System keeps
    /// the user's customisations.
    public var preset: ColaThemePreset = .system

    /// Whether the user has explicitly chosen a body font (via the font panel or
    /// the size stepper). When true, the user's `fontName`/`fontSize` win over a
    /// ColaMD preset's own serif face, so changing the font while an Elegant /
    /// Newsprint preset is active sticks instead of snapping back to the theme's
    /// face — and switching presets no longer resets the font. A preset's font
    /// is still applied as a default until the user makes their own choice.
    public var customFontOverridesPreset: Bool = false

    public init(fontName: String, fontSize: CGFloat, linkBlueHex: String, codeHex: String,
                lineSpacing: CGFloat, paragraphSpacingBefore: CGFloat,
                mathOperatorHex: String = "#D70015", mathNumberHex: String = "#C77800",
                monospaceFontName: String = "", monospaceFontSize: CGFloat = 14,
                standardLigatures: Bool = true, monospaceLigatures: Bool = false,
                antialias: Bool = true,
                preset: ColaThemePreset = .system,
                customFontOverridesPreset: Bool = false) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.linkBlueHex = linkBlueHex
        self.codeHex = codeHex
        self.lineSpacing = lineSpacing
        self.paragraphSpacingBefore = paragraphSpacingBefore
        self.mathOperatorHex = mathOperatorHex
        self.mathNumberHex = mathNumberHex
        self.monospaceFontName = monospaceFontName
        self.monospaceFontSize = monospaceFontSize
        self.standardLigatures = standardLigatures
        self.monospaceLigatures = monospaceLigatures
        self.antialias = antialias
        self.preset = preset
        self.customFontOverridesPreset = customFontOverridesPreset
    }

    // MARK: - Defaults

    public static let `default` = EditorTheme(
        fontName: "Iowan Old Style",
        fontSize: 16,
        linkBlueHex: "#3366E6",
        codeHex: "#8A2425",
        lineSpacing: 4,
        paragraphSpacingBefore: 2
    )

    /// Theme for the Quick Look preview: `.default` but in the system UI font
    /// (`system-ui`, resolved by `HTMLTheme.cssFontStack`) rather than the
    /// editor's serif body face.
    public static let quickLook: EditorTheme = {
        var t = EditorTheme.default
        t.fontName = "system-ui"
        return t
    }()

    // MARK: - UserDefaults Persistence

    private enum Keys {
        static let fontName = "EditorFontName"
        static let fontSize = "EditorFontSize"
        static let monospaceFontName = "EditorMonospaceFontName"
        static let monospaceFontSize = "EditorMonospaceFontSize"
        static let standardLigatures = "EditorStandardLigatures"
        static let monospaceLigatures = "EditorMonospaceLigatures"
        static let antialias = "EditorAntialias"
        static let linkBlueHex = "EditorLinkBlueHex"
        static let codeHex = "EditorCodeHex"
        static let mathOperatorHex = "EditorMathOperatorHex"
        static let mathNumberHex = "EditorMathNumberHex"
        static let lineSpacing = "EditorLineSpacing"
        static let paragraphSpacingBefore = "EditorParagraphSpacingBefore"
        static let customFontOverridesPreset = "EditorCustomFontOverridesPreset"
        // Shared with the app layer's AppSettings.Key.themePreset — the settings
        // picker writes this key, so EditorTheme.load() must read the same one
        // or the chosen preset never reaches the editor.
        static let preset = "settings.appearance.themePreset"
    }

    public static func load(from defaults: UserDefaults = .standard) -> EditorTheme {
        let d = defaults
        let def = EditorTheme.default

        let fontName = d.string(forKey: Keys.fontName) ?? def.fontName
        let fontSize: CGFloat = {
            let v = CGFloat(d.float(forKey: Keys.fontSize))
            return v > 0 ? v : def.fontSize
        }()
        // The accent color is not user-customizable; always use the default so a
        // stale persisted value (e.g. left over from the removed in-app accent
        // picker) can't leak in and recolor links.
        let linkBlueHex = def.linkBlueHex
        let monospaceFontName = d.string(forKey: Keys.monospaceFontName) ?? def.monospaceFontName
        let monospaceFontSize: CGFloat = {
            let v = CGFloat(d.float(forKey: Keys.monospaceFontSize))
            return v > 0 ? v : def.monospaceFontSize
        }()
        let standardLigatures = d.object(forKey: Keys.standardLigatures) as? Bool ?? def.standardLigatures
        let monospaceLigatures = d.object(forKey: Keys.monospaceLigatures) as? Bool ?? def.monospaceLigatures
        let antialias = d.object(forKey: Keys.antialias) as? Bool ?? def.antialias
        let codeHex = d.string(forKey: Keys.codeHex) ?? def.codeHex
        let mathOperatorHex = d.string(forKey: Keys.mathOperatorHex) ?? def.mathOperatorHex
        let mathNumberHex = d.string(forKey: Keys.mathNumberHex) ?? def.mathNumberHex
        let lineSpacing: CGFloat = d.object(forKey: Keys.lineSpacing) != nil
            ? CGFloat(d.float(forKey: Keys.lineSpacing))
            : def.lineSpacing
        let paragraphSpacingBefore: CGFloat = d.object(forKey: Keys.paragraphSpacingBefore) != nil
            ? CGFloat(d.float(forKey: Keys.paragraphSpacingBefore))
            : def.paragraphSpacingBefore
        let presetRaw = d.string(forKey: Keys.preset) ?? ""
        let preset = ColaThemePreset(rawValue: presetRaw) ?? .system
        let customFontOverridesPreset = d.object(forKey: Keys.customFontOverridesPreset) as? Bool ?? false

        return EditorTheme(
            fontName: fontName,
            fontSize: fontSize,
            linkBlueHex: linkBlueHex,
            codeHex: codeHex,
            lineSpacing: lineSpacing,
            paragraphSpacingBefore: paragraphSpacingBefore,
            mathOperatorHex: mathOperatorHex,
            mathNumberHex: mathNumberHex,
            monospaceFontName: monospaceFontName,
            monospaceFontSize: monospaceFontSize,
            standardLigatures: standardLigatures,
            monospaceLigatures: monospaceLigatures,
            antialias: antialias,
            preset: preset,
            customFontOverridesPreset: customFontOverridesPreset
        )
    }

    public func save(to defaults: UserDefaults = .standard) {
        let d = defaults
        d.set(fontName, forKey: Keys.fontName)
        d.set(Float(fontSize), forKey: Keys.fontSize)
        d.set(monospaceFontName, forKey: Keys.monospaceFontName)
        d.set(Float(monospaceFontSize), forKey: Keys.monospaceFontSize)
        d.set(standardLigatures, forKey: Keys.standardLigatures)
        d.set(monospaceLigatures, forKey: Keys.monospaceLigatures)
        d.set(antialias, forKey: Keys.antialias)
        d.set(linkBlueHex, forKey: Keys.linkBlueHex)
        d.set(codeHex, forKey: Keys.codeHex)
        d.set(mathOperatorHex, forKey: Keys.mathOperatorHex)
        d.set(mathNumberHex, forKey: Keys.mathNumberHex)
        d.set(Float(lineSpacing), forKey: Keys.lineSpacing)
        d.set(Float(paragraphSpacingBefore), forKey: Keys.paragraphSpacingBefore)
        d.set(preset.rawValue, forKey: Keys.preset)
        d.set(customFontOverridesPreset, forKey: Keys.customFontOverridesPreset)
    }
}
