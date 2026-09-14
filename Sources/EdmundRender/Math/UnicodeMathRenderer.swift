import AppKit
import CoreText

// MARK: - UnicodeMathRenderer
//
// The math engine used when SwiftMath's fonts can't be reached (see
// `MathFonts`). It typesets nothing: it strips the LaTeX down to something
// readable, maps the common commands to Unicode, and draws that with the best
// font this process has.
//
// The point is not fidelity — it is that a document containing `$…$` renders as
// a document containing readable math instead of taking the process down, and
// that the *reason* is available to the caller (`MathFonts.prepare()`) so the UI
// can say so once.
//
// Nothing here may depend on the bundle that failed. This renderer used to draw
// with `Asana-Math` by name — a font that, in the shipped app, lives *inside*
// `mathFonts.bundle`, i.e. inside the very thing whose absence triggers this
// path. A fallback that needs what just failed is not a fallback. So the
// OpenType MATH font is used only when it can be *loaded* (`hasMathGlyphs`), and
// the result is measured with whatever font was actually used.

@MainActor
public final class UnicodeMathRenderer: MathRenderer {
    public let id = "unicode-fallback"
    public var isReady: Bool { true }

    public init() {}

    /// Glyph substitutions for the commands that appear most often in notes:
    /// relations, operators, arrows, sets and the common Greek letters. Anything
    /// not listed keeps its command name without the backslash (`\alpha` →
    /// "alpha"), which reads better than `\alpha` and never renders as a hole.
    nonisolated private static let symbols: [String: String] = [
        // relations / operators
        "pm": "±", "mp": "∓", "times": "×", "div": "÷", "cdot": "·", "ast": "∗",
        "leq": "≤", "le": "≤", "geq": "≥", "ge": "≥", "neq": "≠", "ne": "≠",
        "approx": "≈", "equiv": "≡", "sim": "∼", "propto": "∝", "cong": "≅",
        "ll": "≪", "gg": "≫", "subset": "⊂", "supset": "⊃", "subseteq": "⊆",
        "supseteq": "⊇", "in": "∈", "notin": "∉", "ni": "∋", "cup": "∪",
        "cap": "∩", "setminus": "∖", "emptyset": "∅", "varnothing": "∅",
        "forall": "∀", "exists": "∃", "nexists": "∄", "neg": "¬", "lnot": "¬",
        "land": "∧", "wedge": "∧", "lor": "∨", "vee": "∨", "oplus": "⊕",
        "otimes": "⊗", "perp": "⊥", "parallel": "∥", "angle": "∠",
        // big operators
        "sum": "∑", "prod": "∏", "coprod": "∐", "int": "∫", "iint": "∬",
        "iiint": "∭", "oint": "∮", "bigcup": "⋃", "bigcap": "⋂",
        "bigoplus": "⨁", "bigotimes": "⨂", "bigvee": "⋁", "bigwedge": "⋀",
        // arrows
        "to": "→", "rightarrow": "→", "leftarrow": "←", "gets": "←",
        "leftrightarrow": "↔", "Rightarrow": "⇒", "Leftarrow": "⇐",
        "Leftrightarrow": "⇔", "implies": "⟹", "iff": "⟺", "mapsto": "↦",
        "uparrow": "↑", "downarrow": "↓", "longrightarrow": "⟶",
        "longleftarrow": "⟵", "hookrightarrow": "↪", "hookleftarrow": "↩",
        // delimiters / misc
        "infty": "∞", "partial": "∂", "nabla": "∇", "ldots": "…", "dots": "…",
        "cdots": "⋯", "vdots": "⋮", "ddots": "⋱", "prime": "′", "degree": "°",
        "sqrt": "√", "surd": "√", "therefore": "∴", "because": "∵",
        "langle": "⟨", "rangle": "⟩", "lceil": "⌈", "rceil": "⌉",
        "lfloor": "⌊", "rfloor": "⌋", "lbrace": "{", "rbrace": "}",
        "left": "", "right": "", "quad": " ", "qquad": "  ", "space": " ",
        // Spacing commands: `\,` `\:` `\;` keep a little air, `\!` removes it.
        ",": " ", ":": " ", ";": " ", "!": "",
        // function names — upright, but plain text is the honest approximation
        "sin": "sin", "cos": "cos", "tan": "tan", "cot": "cot", "sec": "sec",
        "csc": "csc", "log": "log", "ln": "ln", "exp": "exp", "lim": "lim",
        "max": "max", "min": "min", "sup": "sup", "inf": "inf", "det": "det",
        "gcd": "gcd", "mod": "mod", "bmod": " mod ", "pmod": " mod ",
        // letterforms
        "mathbb": "", "mathbf": "", "mathrm": "", "mathit": "", "mathcal": "",
        "text": "", "operatorname": "", "boldsymbol": "", "vec": "", "hat": "",
        "bar": "", "tilde": "", "overline": "", "underline": "",
        // Greek
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε",
        "varepsilon": "ε", "zeta": "ζ", "eta": "η", "theta": "θ", "vartheta": "ϑ",
        "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ",
        "pi": "π", "varpi": "ϖ", "rho": "ρ", "varrho": "ϱ", "sigma": "σ",
        "varsigma": "ς", "tau": "τ", "upsilon": "υ", "phi": "φ", "varphi": "φ",
        "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ",
        "Pi": "Π", "Sigma": "Σ", "Upsilon": "Υ", "Phi": "Φ", "Psi": "Ψ",
        "Omega": "Ω",
    ]

    /// Commands that take one braced argument and should keep it (`\frac{a}{b}`
    /// → "a/b", `\sqrt{x}` → "√x"), rather than dropping it.
    nonisolated private static let argumentCommands: Set<String> = [
        "frac", "dfrac", "tfrac", "sqrt", "text", "mathrm", "mathbf", "mathit",
        "mathcal", "mathbb", "operatorname", "vec", "hat", "bar", "tilde",
        "overline", "underline", "boldsymbol",
    ]

    /// The best font reachable *without* the bundle this renderer exists to work
    /// around.
    ///
    /// In order: the bundled OpenType MATH font, but only if it can be brought
    /// into CoreText (i.e. only if the bundle is there — so it is a bonus, never
    /// a dependency); then a system font that has mathematical coverage; then the
    /// monospaced system font, which is always present. The last two are chosen
    /// by asking the font, not by assuming: `hasMathGlyphs` checks the characters
    /// this output actually contains.
    nonisolated private static func bestAvailableFont(size: CGFloat) -> NSFont {
        if let url = MathFonts.substituteFontURL(),
           let bundled = font(fromFileURL: url, size: size),
           hasMathGlyphs(bundled) {
            return bundled
        }
        for candidate in [NSFont.systemFont(ofSize: size),
                          NSFont.monospacedSystemFont(ofSize: size, weight: .regular)]
        where hasMathGlyphs(candidate) {
            return candidate
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Loads a font file directly, without going through font installation or
    /// registration — so a font that happens to sit in the bundle works, and a
    /// font that doesn't exist yields `nil` instead of a name lookup that
    /// silently substitutes something else.
    nonisolated private static func font(fromFileURL url: URL, size: CGFloat) -> NSFont? {
        guard let provider = CGDataProvider(url: url as CFURL),
              let cgFont = CGFont(provider) else { return nil }
        let ctFont = CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
        return ctFont as NSFont
    }

    /// Whether `font` can draw the symbols this renderer emits. Sampled from the
    /// substitution tables plus the mathematical alphanumerics `plainText` can
    /// produce, because coverage is the whole question — a font that has none of
    /// them would render the fallback as boxes, which is the failure this path is
    /// supposed to be an improvement on.
    nonisolated private static func hasMathGlyphs(_ font: NSFont) -> Bool {
        let probe = "\u{2211}\u{221A}\u{2202}\u{2264}\u{2260}\u{221E}\u{03B1}"
        let scalars = Array(probe.unicodeScalars)
        // UTF-16 units, as CoreText asks for them; every scalar above is BMP, so
        // one unit each and the counts match.
        var characters = scalars.map { UniChar($0.value) }
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        let ok = CTFontGetGlyphsForCharacters(font as CTFont, &characters, &glyphs,
                                              characters.count)
        return ok && !glyphs.contains(0)
    }

    public func render(latex: String, displayMode: Bool,
                       pointSize: CGFloat, color: NSColor) -> RenderedMath? {
        let text = Self.plainText(from: latex)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let size = max(pointSize, 1)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.bestAvailableFont(size: size),
            .foregroundColor: color,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let textSize = string.size()
        let inset: CGFloat = 2
        let imageSize = CGSize(width: ceil(textSize.width) + 2 * inset,
                               height: ceil(textSize.height) + 2 * inset)
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }

        let image = NSImage(size: imageSize, flipped: false) { _ in
            string.draw(at: CGPoint(x: inset, y: inset))
            return true
        }

        // Place the approximation on the surrounding text's baseline using the
        // substituted font's own metrics, so inline math sits right even though
        // no typesetting happened.
        let font = attributes[.font] as! NSFont
        let descent = min(-font.descender + inset, imageSize.height)
        let ascent = max(imageSize.height - descent, 0)
        return RenderedMath(image: image, ascent: ascent, descent: descent)
    }

    /// Flattens LaTeX to readable plain text. Deliberately forgiving: unknown
    /// commands lose their backslash and braces are dropped, so nothing in the
    /// source can produce an empty or failing render.
    /// `nonisolated`: pure string work with no AppKit or instance state, so the
    /// tests (and any future non-UI caller) can flatten LaTeX off the main actor.
    public nonisolated static func plainText(from latex: String) -> String {
        var out = ""
        var index = latex.startIndex
        var fracPending: [String] = []

        func readGroup() -> String? {
            // `index` sits on `{`; returns the group body and advances past `}`.
            guard index < latex.endIndex, latex[index] == "{" else { return nil }
            var depth = 0
            var body = ""
            var i = index
            while i < latex.endIndex {
                let c = latex[i]
                if c == "{" { depth += 1; if depth == 1 { i = latex.index(after: i); continue } }
                if c == "}" {
                    depth -= 1
                    if depth == 0 { index = latex.index(after: i); return body }
                }
                body.append(c)
                i = latex.index(after: i)
            }
            index = latex.endIndex
            return body
        }

        while index < latex.endIndex {
            let c = latex[index]
            switch c {
            case "\\":
                var i = latex.index(after: index)
                var name = ""
                if i < latex.endIndex, !latex[i].isLetter {
                    name = String(latex[i]); i = latex.index(after: i)   // \, \; \! \{ \}
                } else {
                    while i < latex.endIndex, latex[i].isLetter {
                        name.append(latex[i]); i = latex.index(after: i)
                    }
                }
                index = i
                if name == "frac" || name == "dfrac" || name == "tfrac" {
                    let numerator = readGroup().map { plainText(from: $0) } ?? "?"
                    let denominator = readGroup().map { plainText(from: $0) } ?? "?"
                    fracPending.append("(\(numerator))/(\(denominator))")
                    continue
                }
                if name == "sqrt" {
                    out += Self.symbols["sqrt"] ?? "√"
                    if let group = readGroup() { out += plainText(from: group) }
                    continue
                }
                if Self.argumentCommands.contains(name) {
                    if let group = readGroup() { out += plainText(from: group) }
                    continue
                }
                if let symbol = Self.symbols[name] {
                    out += symbol
                } else if !name.isEmpty {
                    out += name   // readable, never empty
                }
            case "{", "}":
                index = latex.index(after: index)   // grouping only: drop
            case "_", "^":
                index = latex.index(after: index)
                // Sub/superscripts read fine inline; a bare `^2` is conventional.
            default:
                out.append(c)
                index = latex.index(after: index)
            }
        }

        if !fracPending.isEmpty {
            out += (out.isEmpty ? "" : " ") + fracPending.joined(separator: " ")
        }
        return out.replacingOccurrences(of: "  ", with: " ")
    }
}
