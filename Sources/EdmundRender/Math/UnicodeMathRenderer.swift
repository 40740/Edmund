import AppKit

// MARK: - UnicodeMathRenderer
//
// The last-resort engine: LaTeX flattened into readable Unicode, drawn with a
// system font. It exists so a document containing `$…$` always shows
// *something* — a page with a hole where an equation should be reads as a
// broken document, and before issue #12 the alternative was a crash.
//
// It is not typesetting. `\frac{a}{b}` becomes `(a)/(b)`, superscripts become
// Unicode superscripts where they exist, and anything it doesn't recognise is
// passed through as source. That is deliberate: a flattened equation is
// obviously approximate, which is what tells the reader that the real engine
// is missing, rather than quietly pretending to be correct.
//
// Font: the only math font guaranteed to be present is the system's, so this
// never touches the bundled fonts — it draws with whatever AppKit gives for the
// requested size, which is also why it can't fail and can't trap.
@MainActor
public final class UnicodeMathRenderer: MathRenderer {
    public let id = "unicode"

    /// Always ready: it needs no resources. This is the property that makes the
    /// fallback chain total.
    public var isReady: Bool { true }

    public init() {}

    /// Flattens `latex` and draws it. Never returns `nil` for non-empty input.
    public func render(latex: String, displayMode: Bool,
                       pointSize: CGFloat, color: NSColor) -> RenderedMath? {
        let text = UnicodeMathRenderer.flatten(latex)
        guard !text.isEmpty else { return nil }

        let font = NSFont.systemFont(ofSize: pointSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let size = attributed.size()
        let inset: CGFloat = 1
        let imageSize = CGSize(width: ceil(size.width) + inset * 2,
                               height: ceil(size.height) + inset * 2)

        let image = NSImage(size: imageSize, flipped: false) { _ in
            attributed.draw(at: CGPoint(x: inset, y: inset))
            return true
        }
        // The system font's own metrics put the baseline the usual way; the
        // caller only needs ascent + descent == height.
        let ascent = font.ascender + inset
        let descent = imageSize.height - ascent
        return RenderedMath(image: image, ascent: ascent, descent: descent)
    }

    // MARK: - Flattening

    private static let superscripts: [Character: String] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶",
        "7": "⁷", "8": "⁸", "9": "⁹", "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽",
        ")": "⁾", "n": "ⁿ", "i": "ⁱ",
    ]
    private static let subscripts: [Character: String] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆",
        "7": "₇", "8": "₈", "9": "₉", "+": "₊", "-": "₋", "=": "₌", "(": "₍",
        ")": "₎", "a": "ₐ", "e": "ₑ", "i": "ᵢ", "j": "ⱼ", "k": "ₖ", "l": "ₗ",
        "m": "ₘ", "n": "ₙ", "o": "ₒ", "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ",
        "u": "ᵤ", "v": "ᵥ", "x": "ₓ",
    ]
    private static let symbols: [String: String] = [
        "\\alpha": "α", "\\beta": "β", "\\gamma": "γ", "\\delta": "δ",
        "\\epsilon": "ε", "\\varepsilon": "ε", "\\zeta": "ζ", "\\eta": "η",
        "\\theta": "θ", "\\vartheta": "ϑ", "\\iota": "ι", "\\kappa": "κ",
        "\\lambda": "λ", "\\mu": "μ", "\\nu": "ν", "\\xi": "ξ", "\\pi": "π",
        "\\varpi": "ϖ", "\\rho": "ρ", "\\varrho": "ϱ", "\\sigma": "σ",
        "\\varsigma": "ς", "\\tau": "τ", "\\upsilon": "υ", "\\phi": "φ",
        "\\varphi": "φ", "\\chi": "χ", "\\psi": "ψ", "\\omega": "ω",
        "\\Gamma": "Γ", "\\Delta": "Δ", "\\Theta": "Θ", "\\Lambda": "Λ",
        "\\Xi": "Ξ", "\\Pi": "Π", "\\Sigma": "Σ", "\\Upsilon": "Υ",
        "\\Phi": "Φ", "\\Psi": "Ψ", "\\Omega": "Ω",
        "\\times": "×", "\\div": "÷", "\\pm": "±", "\\mp": "∓", "\\cdot": "·",
        "\\ast": "∗", "\\star": "⋆", "\\circ": "∘", "\\bullet": "•",
        "\\leq": "≤", "\\le": "≤", "\\geq": "≥", "\\ge": "≥", "\\neq": "≠",
        "\\ne": "≠", "\\approx": "≈", "\\equiv": "≡", "\\sim": "∼",
        "\\simeq": "≃", "\\cong": "≅", "\\propto": "∝", "\\ll": "≪", "\\gg": "≫",
        "\\infty": "∞", "\\partial": "∂", "\\nabla": "∇", "\\sum": "∑",
        "\\prod": "∏", "\\int": "∫", "\\oint": "∮", "\\sqrt": "√",
        "\\in": "∈", "\\notin": "∉", "\\ni": "∋", "\\subset": "⊂",
        "\\supset": "⊃", "\\subseteq": "⊆", "\\supseteq": "⊇", "\\cup": "∪",
        "\\cap": "∩", "\\emptyset": "∅", "\\forall": "∀", "\\exists": "∃",
        "\\neg": "¬", "\\land": "∧", "\\lor": "∨", "\\to": "→",
        "\\rightarrow": "→", "\\leftarrow": "←", "\\leftrightarrow": "↔",
        "\\Rightarrow": "⇒", "\\Leftarrow": "⇐", "\\Leftrightarrow": "⇔",
        "\\mapsto": "↦", "\\ldots": "…", "\\cdots": "⋯", "\\dots": "…",
        "\\angle": "∠", "\\perp": "⊥", "\\parallel": "∥", "\\triangle": "△",
        "\\prime": "′", "\\hbar": "ℏ", "\\ell": "ℓ", "\\Re": "ℜ", "\\Im": "ℑ",
        "\\aleph": "ℵ", "\\mathbb{R}": "ℝ", "\\mathbb{N}": "ℕ",
        "\\mathbb{Z}": "ℤ", "\\mathbb{Q}": "ℚ", "\\mathbb{C}": "ℂ",
        "\\quad": "  ", "\\qquad": "    ", "\\,": " ", "\\;": " ",
        "\\:": " ", "\\!": "", "\\left": "", "\\right": "",
        "\\displaystyle": "", "\\textstyle": "", "\\limits": "",
    ]

    /// Flattens LaTeX to readable Unicode. Public for the tests, which assert
    /// the approximation is legible and never empty for real input.
    public static func flatten(_ latex: String) -> String {
        var out = ""
        var i = latex.startIndex

        while i < latex.endIndex {
            let ch = latex[i]

            if ch == "\\" {
                // A command: read the name, then its argument if it takes one.
                let nameStart = latex.index(after: i)
                var j = nameStart
                while j < latex.endIndex, latex[j].isLetter { j = latex.index(after: j) }
                let name = String(latex[i..<j])

                var k = j
                while k < latex.endIndex, latex[k] == " " { k = latex.index(after: k) }
                let arg = k < latex.endIndex ? latex[k] : nil

                switch name {
                case "\\frac", "\\dfrac", "\\tfrac":
                    if let (num, afterNum) = bracedArgument(latex, from: k) {
                        if let (den, afterDen) = bracedArgument(latex, from: afterNum) {
                            out += "(\(flatten(num)))/(\(flatten(den)))"
                            i = afterDen
                            continue
                        }
                    }
                case "\\sqrt":
                    if let (radicand, after) = bracedArgument(latex, from: k) {
                        out += "√(\(flatten(radicand)))"
                        i = after
                        continue
                    }
                case "\\text", "\\mathrm", "\\mathbf", "\\mathit", "\\operatorname":
                    if let (body, after) = bracedArgument(latex, from: k) {
                        out += body
                        i = after
                        continue
                    }
                case "\\hat", "\\bar", "\\vec", "\\dot", "\\tilde", "\\overline":
                    if let (body, after) = bracedArgument(latex, from: k) {
                        let accent = name == "\\bar" || name == "\\overline" ? "\u{0304}" : "\u{0302}"
                        out += flatten(body) + accent
                        i = after
                        continue
                    }
                default:
                    if name.isEmpty, let arg {
                        // A bare escaped character (`\{`, `\%`, `\_`).
                        out.append(arg)
                        i = latex.index(after: k)
                        continue
                    }
                }

                if let replacement = symbols[name] {
                    out += replacement
                } else if !name.isEmpty {
                    // Unknown command: keep it visible rather than dropping it,
                    // so the reader can see what the source asked for.
                    out += name
                    if name == "\\begin" || name == "\\end" {
                        if let (env, after) = bracedArgument(latex, from: k) {
                            out += "{" + env + "}"
                            i = after
                            continue
                        }
                    }
                }
                i = j
                continue
            }

            if ch == "^" || ch == "_" {
                let table = ch == "^" ? superscripts : subscripts
                let after = latex.index(after: i)
                if let (body, end) = bracedArgument(latex, from: after) {
                    out += mapToTable(flatten(body), table)
                    i = end
                    continue
                }
                if after < latex.endIndex {
                    out += mapToTable(flatten(String(latex[after])), table)
                    i = latex.index(after: after)
                    continue
                }
            }

            if ch == "{" || ch == "}" {
                i = latex.index(after: i)   // grouping is implicit when flattened
                continue
            }

            out.append(ch)
            i = latex.index(after: i)
        }

        // Collapse the spaces the substitutions above can leave around.
        return out
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func mapToTable(_ s: String, _ table: [Character: String]) -> String {
        var out = ""
        for c in s { out += table[c] ?? String(c) }
        return out
    }

    /// Reads a `{…}` group (or a single token) starting at `index`, returning its
    /// contents and the index just past it.
    private static func bracedArgument(_ s: String, from index: String.Index)
        -> (String, String.Index)? {
        guard index < s.endIndex else { return nil }
        if s[index] == "{" {
            var depth = 0
            var i = index
            let start = s.index(after: index)
            while i < s.endIndex {
                if s[i] == "{" { depth += 1 }
                else if s[i] == "}" {
                    depth -= 1
                    if depth == 0 { return (String(s[start..<i]), s.index(after: i)) }
                }
                i = s.index(after: i)
            }
            return (String(s[start...]), s.endIndex)
        }
        let end = s.index(after: index)
        return (String(s[index..<end]), end)
    }
}
