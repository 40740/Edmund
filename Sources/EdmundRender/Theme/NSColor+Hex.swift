import AppKit

// MARK: - NSColor Hex Helpers
//
// The `#RRGGBB` ↔ `NSColor` bridge. Used by `EditorTheme`'s AppKit halves and
// by the HTML renderer; lives in EdmundCore so that `EdmundMarkdown` (the
// parsing/model half the Quick Look preview links) stays free of AppKit.

extension NSColor {

    /// Create a color from a hex string like "#3366E6" or "3366E6".
    ///
    /// sRGB, not the calibrated space: a hex literal means the same thing in CSS
    /// (Read mode, PDF export) as it does here, and calibrated RGB composites
    /// visibly lighter than that — every project hex drifted, most obviously the
    /// `warning` callout's orange (#EC7500 painted as #F28900 in the editor while
    /// Read mode showed the literal). Decoding as sRGB makes the two agree and
    /// makes hex → NSColor → `hexString` round-trip exactly.
    public convenience init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let rgb = UInt64(h, radix: 16) else { return nil }
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    /// Returns the hex string representation (e.g. "#3366E6").
    public var hexString: String {
        guard let rgb = usingColorSpace(.deviceRGB) else { return "#000000" }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
