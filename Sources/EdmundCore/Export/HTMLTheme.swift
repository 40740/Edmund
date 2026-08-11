import AppKit

// MARK: - HTMLTheme
//
// Emits the CSS for Read mode / PDF export from the *same* `EditorTheme` and
// `CalloutStyle` models the editor renders from, so the two can't drift. The
// theme is the single source of truth for the values it carries (body font/size,
// accent, code color, line/paragraph spacing, callout colors); spacing for
// elements the theme doesn't model (headings, list indent) uses tasteful
// document defaults.
//
// Colors are resolved for one appearance (`dark`); the Read view re-renders when
// the system appearance flips.
enum HTMLTheme {

    /// The page background hex for the given appearance — shared by the CSS
    /// `--bg` variable and `ReadModeWebView.underPageBackgroundColor` so the
    /// webview's own background can't drift from the page it's about to show.
    ///
    /// Routes by preset: ColaMD's Elegant theme paints a warm-paper page
    /// (`#f0edea` light / `#1c1a18` dark) instead of the default white /
    /// `#292929`. The same hex reaches `underPageBackgroundColor`, killing the
    /// white flash before first paint in either look.
    private static func backgroundHex(dark: Bool, preset: ThemePreset = .edmund) -> String {
        switch preset {
        case .edmund:
            return dark ? "#292929" : "#ffffff"
        case .colaElegant:
            return dark ? "#1c1a18" : "#f0edea"
        }
    }

    /// `NSColor` form of `backgroundHex`, for `WKWebView.underPageBackgroundColor`.
    /// Resolves the preset from the live theme so a preset switch updates the
    /// flash color along with the page.
    @MainActor
    static func backgroundColor(dark: Bool, preset: ThemePreset = .edmund) -> NSColor {
        NSColor(hex: backgroundHex(dark: dark, preset: preset)) ?? .textBackgroundColor
    }

    @MainActor
    static func css(_ theme: EditorTheme,
                    callouts: [String: CalloutStyle],
                    dark: Bool,
                    maxContentWidthPoints: Double = .greatestFiniteMagnitude) -> String {
        // Route by preset: ColaMD Elegant has its own complete stylesheet
        // (warm paper, terracotta accent, serif body, One-Dark code panel) that
        // can't be expressed as a recolor of the Edmund CSS — spacing, blockquote
        // treatment, table chrome and code-block padding all differ. Dispatching
        // here keeps the existing call sites (`DocumentHTML.full`, `MarkdownPrinter`,
        // `ReadModeWebView.underPageBackgroundColor`) preset-agnostic.
        switch theme.preset {
        case .edmund:
            return edmundCSS(theme, callouts: callouts, dark: dark,
                             maxContentWidthPoints: maxContentWidthPoints)
        case .colaElegant:
            return colaElegantCSS(theme, callouts: callouts, dark: dark,
                                  maxContentWidthPoints: maxContentWidthPoints)
        }
    }

    // MARK: - Edmund (default) CSS

    @MainActor
    private static func edmundCSS(_ theme: EditorTheme,
                                  callouts: [String: CalloutStyle],
                                  dark: Bool,
                                  maxContentWidthPoints: Double) -> String {
        let bg = backgroundHex(dark: dark, preset: .edmund)
        // Body ink comes from the editor's own definition, not a second hex, so
        // Edit and Read mode can never drift apart again (EditorTheme
        // .bodyTextColor). This was `#1a1a1a` in light mode, 10% lighter than
        // what the editor paints.
        let fg = EditorTheme.bodyTextColorResolved(dark: dark).hexString
        let faint = dark ? "#9a9a9a" : "#6a6a6a"
        let rule = dark ? "#3a3a3a" : "#e0e0e0"
        // Markers, rules and table borders in dark mode: the same gray the editor
        // draws them at (EditorTextView.darkChromeGray, 0.41 white).
        let darkChrome = "#696969"
        // Rules and table borders sit a step dimmer (EditorTextView.darkRuleGray).
        let darkRule = "#555555"
        // #2a2a2a sat one level above the #292929 page background — code blocks
        // and table header rows had no visible tint at all in dark mode.
        let codeBg = dark ? "#333333" : "#f4f4f4"

        // line-height: editor `NSParagraphStyle.lineSpacing` adds extra points
        // *between* lines on top of the font's natural line height. That natural
        // height is MEASURED from the resolved font, not assumed — this used to
        // hardcode 1.2×, but Iowan Old Style (the default body face) is 1.375×,
        // so every Read-mode line came out ~11% tighter than the editor's and the
        // font-size stepper moved the two modes apart instead of together.
        //
        // `defaultLineHeight`, NOT `ascender - descender + leading`: the two
        // disagree (Iowan 22.0 vs 21.84; Helvetica 19.0 vs 16.0 — a 19% gap), and
        // measuring real TextKit 2 line fragments shows the layout matches
        // `defaultLineHeight` for every face tried. It's the TextKit 1 class, used
        // here purely as the metrics oracle that agrees with TextKit 2's layout.
        let naturalLineHeight = NSLayoutManager().defaultLineHeight(for: theme.bodyFont)
        let lineHeight = (naturalLineHeight + theme.lineSpacing) / theme.fontSize

        // CSS px and AppKit points are both device-independent, so the editor's
        // physical cap (EditorTextView.maxContentWidthPoints) carries over as-is.
        // A huge/infinite value means "uncapped" in the editor too; `none` skips
        // the constraint instead of emitting an unusable giant number.
        let pageMaxWidth = maxContentWidthPoints < 100_000
            ? "\(trim(CGFloat(maxContentWidthPoints)))px" : "none"

        return """
        :root {
          --body-font: \(cssFontStack(theme.fontName, generic: "serif"));
          --body-size: \(trim(theme.fontSize))px;
          --mono-font: \(cssFontStack(theme.monospaceFontName.isEmpty ? "ui-monospace" : theme.monospaceFontName, generic: "monospace"));
          --mono-size: \(trim(theme.monospaceFontSize))px;
          --accent: \(theme.linkBlueHex);
          --code: \(theme.codeHex);
          --bg: \(bg);
          --fg: \(fg);
          --faint: \(faint);
          --rule: \(rule);
          --code-bg: \(codeBg);
          /* Inline code sits directly on --bg, where the block --code-bg is only
             one level lighter and reads as nothing; dark mode needs its own step. */
          --inline-code-bg: \(dark ? "#3c3c3c" : codeBg);
          --marker: \(dark ? darkChrome : resolvedRGBA(.tertiaryLabelColor, dark: dark));
          --table-border: \(dark ? darkRule : rule);
          --hr: \(dark ? "#4a4a4a" : rule);
          --quote-bar: \(dark ? darkChrome : rule);
          --check-fill: \(resolvedRGBA(.controlAccentColor, dark: dark));
          --line-height: \(trim(lineHeight));
          --para-space: \(trim(max(theme.paragraphSpacingBefore, 0)))px;
          --page-max-width: \(pageMaxWidth);
        }
        \(calloutVars(callouts, dark: dark))
        \(staticRules)
        \(codeTokenRules(dark: dark))
        """
    }

    // MARK: Code syntax colors

    /// `.tok-*` color rules for fenced code blocks, from the shared
    /// `CodeSyntaxPalette` so Read mode matches the editor token-for-token. The
    /// `pre code` rule overrides the static `var(--fg)` so plain (un-tokenized)
    /// code uses the palette's plain color too, like the editor.
    private static func codeTokenRules(dark: Bool) -> String {
        func rule(_ selector: String, _ type: CodeHighlighter.TokenType?) -> String {
            "\(selector) { color: \(CodeSyntaxPalette.hex(type, dark: dark)); }"
        }
        return [
            rule("pre code", nil),
            rule("pre code .tok-keyword", .keyword),
            rule("pre code .tok-command", .command),
            rule("pre code .tok-type", .type),
            rule("pre code .tok-attribute", .attribute),
            rule("pre code .tok-variable", .variable),
            rule("pre code .tok-value", .value),
            rule("pre code .tok-number", .number),
            rule("pre code .tok-string", .string),
            rule("pre code .tok-comment", .comment),
        ].joined(separator: "\n")
    }

    // MARK: - ColaMD "Elegant Plus" CSS
    //
    // A complete stylesheet for the ColaMD Elegant preset, ported from
    // https://github.com/marswaveai/ColaMD/blob/main/themes/elegant.css and the
    // design spec in `UI-设计文档.md`. Independent from `edmundCSS` because the
    // look differs in kind, not just in color: paper-warm background, generous
    // 0.04em tracking, 1.9 line-height, 4px terracotta blockquote bar, dark
    // code panel with 20/24px breathing room, terracotta-tinted table headers,
    // and One-Dark syntax colors. Same `EditorTheme` fields feed both paths so
    // user font/size/spacing tweaks still apply.
    @MainActor
    private static func colaElegantCSS(_ theme: EditorTheme,
                                       callouts: [String: CalloutStyle],
                                       dark: Bool,
                                       maxContentWidthPoints: Double) -> String {
        // Palette tokens — see UI-设计文档.md §2. Each appearance has its own
        // accent ramp: the terracotta is lifted in dark mode so it reads
        // against the warm-black page (#1c1a18, not pure black).
        let bg           = dark ? "#1c1a18" : "#f0edea"
        let bgSoft       = dark ? "#26231f" : "#eae6e1"
        let text         = dark ? "#d8d3ce" : "#2c2c2c"
        let textSoft     = dark ? "#a89f96" : "#555555"
        let heading      = dark ? "#e0dcd7" : "#1a1a1a"
        let accent       = dark ? "#e0653f" : "#c44b2b"
        let accentSoft   = dark ? "rgba(224, 101, 63, 0.18)" : "rgba(196, 75, 43, 0.15)"
        let selection    = dark ? "rgba(224, 101, 63, 0.25)" : "rgba(196, 75, 43, 0.20)"
        let border       = dark ? "#3a342e" : "#d8d3ce"
        let codeBg       = dark ? "#14110f" : "#2c2c2c"
        let codeFg       = "#e0dcd7"
        let inlineCodeBg = dark ? "#2a2622" : "#e8e4df"
        let hrGlow       = accent

        // Body font: prefer the user's picked family (Songti SC by default),
        // then macOS CJK serifs (Source Han Serif, Songti SC, SimSun), then a
        // Latin serif fallback chain. LXGW WenKai goes first if the user has
        // installed it — it's the design doc's preferred face.
        let bodyStack = cssFontStack(theme.fontName, generic: "serif")
        // Mono stack: JetBrains Mono → Fira Code → SF Mono → Menlo → system mono.
        // The user's monospaceFontName is honored if non-empty.
        let monoName = theme.monospaceFontName.isEmpty ? "Menlo" : theme.monospaceFontName
        let monoStack = "\"\(monoName)\", \"JetBrains Mono\", \"Fira Code\", \"SF Mono\", ui-monospace, Menlo, Consolas, monospace"

        // line-height: the editor measures the natural line height of the body
        // font, then adds `theme.lineSpacing` between lines. The ColaMD preset
        // sets `lineSpacing = 8.4` which (for Songti SC at 16pt) lands at the
        // spec's 1.9 cadence; we compute it the same way `edmundCSS` does so
        // the size stepper keeps Edit and Read in lockstep.
        let naturalLineHeight = NSLayoutManager().defaultLineHeight(for: theme.bodyFont)
        let lineHeight = (naturalLineHeight + theme.lineSpacing) / theme.fontSize

        let pageMaxWidth = maxContentWidthPoints < 100_000
            ? "\(trim(CGFloat(maxContentWidthPoints)))px" : "none"

        return """
        :root {
          --cola-bg: \(bg);
          --cola-bg-soft: \(bgSoft);
          --cola-text: \(text);
          --cola-text-soft: \(textSoft);
          --cola-accent: \(accent);
          --cola-accent-soft: \(accentSoft);
          --cola-border: \(border);
          --cola-code-bg: \(codeBg);
          --cola-code-text: \(codeFg);
          --cola-inline-code-bg: \(inlineCodeBg);
          --cola-selection: \(selection);
          --cola-heading: \(heading);
          --body-font: \(bodyStack);
          --body-size: \(trim(theme.fontSize))px;
          --mono-font: \(monoStack);
          --mono-size: \(trim(theme.monospaceFontSize))px;
          --line-height: \(trim(lineHeight));
          --page-max-width: \(pageMaxWidth);
        }
        \(calloutVars(callouts, dark: dark))
        \(colaStaticRules(hrGlow: hrGlow))
        \(colaCodeTokenRules(dark: dark))
        """
    }

    /// Static element rules for the ColaMD Elegant theme. Transcribed verbatim
    /// from the design spec (UI-设计文档.md §4). Every value is the spec's
    /// literal value — no reference-CSS fallbacks, no simplifications.
    private static func colaStaticRules(hrGlow: String) -> String {
        return """
        * { box-sizing: border-box; }
        html { -webkit-text-size-adjust: 100%; -webkit-font-smoothing: antialiased; }
        body {
          font-family: var(--body-font);
          font-size: var(--body-size);
          line-height: var(--line-height);
          letter-spacing: 0.04em;
          color: var(--cola-text);
          background: var(--cola-bg);
          margin: 0;
          padding: 30px 24px 100px;
        }
        ::selection { background: var(--cola-selection); }
        .page { max-width: var(--page-max-width); margin: 0 auto; }

        /* §4.1 段落: margin 0.85em, text-align justify, letter-spacing 0.04em */
        p {
          margin: 0 0 1em;
          text-align: justify;
          letter-spacing: 0.04em;
        }

        /* §3.2 / §4.1 标题: #1a1a1a, 700, line-height 1.4, letter-spacing 0.02em,
           margin 1.8em 0 0.65em. h1/h2 带下划线 (padding-bottom + border-bottom). */
        h1, h2, h3, h4, h5, h6 {
          color: var(--cola-heading);
          font-weight: 700;
          line-height: 1.4;
          letter-spacing: 0.02em;
          margin: 1.8em 0 0.65em;
        }
        h1 { font-size: 1.8em; padding-bottom: 0.3em; border-bottom: 1px solid var(--cola-border); }
        h2 { font-size: 1.5em; padding-bottom: 0.2em; border-bottom: 1px solid var(--cola-border); }
        h3 { font-size: 1.25em; }
        h4 { font-size: 1.1em; }
        h5 { font-size: 1em; }
        h6 { font-size: 0.95em; color: var(--cola-text-soft); }
        :is(h1, h2, h3, h4, h5, h6):first-child { margin-top: 0; }

        /* §4 强调: strong #c44b2b, em #444 */
        strong, b { color: var(--cola-accent); font-weight: 700; }
        em { font-style: italic; color: var(--cola-text-soft); }
        em strong, strong em { color: var(--cola-accent); }

        /* §4.7 链接: #c44b2b, hover 下划线展开动效 background-size 0%→100% 0.3s */
        a {
          color: var(--cola-accent);
          text-decoration: none;
          background-image: linear-gradient(currentColor, currentColor);
          background-size: 0% 1px;
          background-position: 0 100%;
          background-repeat: no-repeat;
          transition: background-size .3s ease;
        }
        a:hover { background-size: 100% 1px; }

        /* §4.7 <u>: 2px solid #c44b2b */
        u { text-decoration: none; border-bottom: 2px solid var(--cola-accent); padding-bottom: 1px; }

        /* §4.7 del: #555, line-through #c44b2b, opacity 0.75 */
        del, s { color: var(--cola-text-soft); text-decoration: line-through var(--cola-accent); opacity: 0.75; }

        /* §4.5 引用块: padding 16px 22px 16px 26px (上下对称16px),
           border-left 4px solid #c44b2b, background #eae6e1, color #555,
           border-radius 0 6px 6px 0, margin 1.6em 0.
           hover: border-left-width 4px→5px */
        blockquote {
          margin: 1.6em 0;
          padding: 16px 22px 16px 26px;
          border-left: 4px solid var(--cola-accent);
          background: var(--cola-bg-soft);
          color: var(--cola-text-soft);
          border-radius: 0 6px 6px 0;
          transition: border-left-width .15s ease;
        }
        blockquote:hover { border-left-width: 5px; }
        blockquote > p:first-child { margin-top: 0; }
        blockquote > p:last-child  { margin-bottom: 0; }
        blockquote > p { margin: 0.5em 0; }
        blockquote > blockquote:last-child,
        .callout-body > blockquote:last-child { margin-bottom: 0; }

        /* §4.7 hr: 渐变 transparent→#d8d3ce 20%→80%→transparent, 高1px,
           中心6px圆点 #c44b2b 50%透明 */
        hr {
          position: relative;
          border: none;
          height: 1px;
          margin: 2.5em 0;
          background: linear-gradient(to right,
            transparent 0%,
            var(--cola-border) 20%,
            var(--cola-border) 80%,
            transparent 100%);
        }
        hr::after {
          content: "";
          position: absolute;
          top: 50%; left: 50%;
          width: 6px; height: 6px;
          transform: translate(-50%, -50%);
          background: \(hrGlow);
          opacity: 0.5;
          border-radius: 50%;
        }

        /* §4.1 列表: ul/ol margin 0.85em, padding-left 1.8em; li margin 0.4em, line-height 1.85 */
        ul, ol { margin: 0.85em 0; padding-left: 1.8em; }
        li { margin: 0.4em 0; line-height: 1.85; letter-spacing: 0.02em; }
        li > p { margin: 0; }
        li > ul, li > ol { margin: 0.4em 0; }
        ul { list-style-type: disc; list-style-position: outside; }
        ol { list-style-type: decimal; list-style-position: outside; }
        li::marker { color: var(--cola-text-soft); font-size: 0.85em; }
        ol > li::marker { font-size: 1em; color: var(--cola-text); }

        /* Task items */
        li.task { list-style: none; }
        li.task > .task-check {
          float: left; width: 1.2em; height: 1.2em; line-height: 0;
          margin-top: 0.1em; margin-right: 0.3em; margin-left: -1.45em;
        }
        li.task > .task-check svg { display: block; width: 1.2em; height: 1.2em; }
        .task-check--unchecked { color: var(--cola-text-soft); }
        .task-check--checked   { color: var(--cola-accent); }
        li.task--checked > p { opacity: 0.45; text-decoration: line-through; }
        li.task > p { display: inline; margin: 0; }
        li.task > ul, li.task > ol { clear: left; }
        li.task::after { content: ""; display: block; clear: both; }
        .blank-line { height: calc(var(--body-size) * var(--line-height)); }

        /* §4.3 行内代码: padding 3px 8px, margin 2px 2px, background #e8e4df,
           color #c44b2b, border-radius 4px, font-size 0.88em */
        code, tt {
          font-family: var(--mono-font);
          font-size: 0.88em;
          padding: 3px 8px;
          margin: 0 2px;
          background: var(--cola-inline-code-bg);
          color: var(--cola-accent);
          border-radius: 4px;
          letter-spacing: 0;
        }

        /* §4.2 代码块: padding 20px 24px, background #2c2c2c, color #e0dcd7,
           border-radius 8px, margin 1.6em 0, font-size 0.88em, line-height 1.65,
           tab-size 4, overflow-x auto */
        pre {
          font-family: var(--mono-font);
          font-size: 0.88em;
          line-height: 1.65;
          background: var(--cola-code-bg);
          color: var(--cola-code-text);
          padding: 20px 24px;
          border-radius: 8px;
          margin: 1.6em 0;
          overflow-x: auto;
          tab-size: 4; -moz-tab-size: 4;
          letter-spacing: 0;
        }
        pre code {
          background: transparent;
          color: inherit;
          padding: 0;
          margin: 0;
          border-radius: 0;
          font-size: var(--mono-size);
        }
        /* Copy button — top-right, hover-revealed */
        .code-block-wrap { position: relative; margin: 1.6em 0; }
        .code-block-wrap pre { margin: 0; }
        .code-copy-btn {
          position: absolute; top: 8px; right: 10px;
          display: flex; align-items: center; gap: 4px;
          font-family: var(--mono-font); font-size: 11px; font-weight: 500;
          color: rgba(224, 220, 215, 0.7);
          background: rgba(255, 255, 255, 0.06);
          padding: 3px 6px; border-radius: 5px;
          text-decoration: none; cursor: pointer;
        }
        .code-copy-btn:hover { background: rgba(255, 255, 255, 0.14); color: #fff; }
        .code-copy-btn.copied { color: var(--cola-accent); }
        .code-copy-btn svg { width: 13px; height: 13px; stroke: currentColor; }
        .code-copy-icon { opacity: 0; transition: opacity .15s; }
        .code-block-wrap:hover .code-copy-icon { opacity: 1; }

        /* §4.4 高亮 Mark: padding 3px 8px (原1px 4px→加大), background rgba(196,75,43,0.15),
           color inherit, border-radius 4px, margin 0 1px, box-decoration-break clone */
        mark {
          background: var(--cola-accent-soft);
          color: inherit;
          padding: 3px 8px;
          border-radius: 4px;
          margin: 0 1px;
          -webkit-box-decoration-break: clone;
          box-decoration-break: clone;
        }

        /* Tag pill */
        .tag {
          color: var(--cola-accent);
          background: color-mix(in srgb, var(--cola-accent) 14%, transparent);
          padding: 0.05em 0.5em; border-radius: 0.8em;
          font-size: 0.88em; white-space: nowrap;
        }

        /* §4.7 kbd: padding 3px 7px, border 1px solid, border-bottom-width 2px,
           border-radius 5px, box-shadow 0 1px 0 rgba(0,0,0,0.06) */
        kbd {
          font-family: var(--mono-font);
          font-size: 0.92em;
          background: var(--cola-bg-soft);
          color: var(--cola-text);
          border: 1px solid var(--cola-border);
          border-bottom-width: 2px;
          border-radius: 5px;
          padding: 3px 7px;
          box-shadow: 0 1px 0 rgba(0, 0, 0, 0.06);
        }
        sub, sup { font-size: 0.75em; line-height: 0; position: relative; vertical-align: baseline; }
        sup { top: -0.5em; }
        sub { bottom: -0.25em; }

        /* §4.7 脚注: font-size 0.85em, color #555, 顶部 1px solid #d8d3ce 分隔 */
        sup.footnote-ref a { text-decoration: none; color: var(--cola-accent); }
        hr.footnotes-sep { margin-bottom: 0.8em; }
        hr.footnotes-sep::after { display: none; }
        ol.footnotes { font-size: 0.85em; color: var(--cola-text-soft); }
        ol.footnotes li { margin: 0.4em 0; }
        a.footnote-backref { text-decoration: none; margin-left: 0.2em; font-size: 0.9em; line-height: 1; color: var(--cola-accent); }

        /* §4.7 图片: max-width 100%, border-radius 8px, margin 1.6em auto */
        img { max-width: 100%; border-radius: 8px; }
        p > img:only-child { display: block; margin: 1.6em auto; }
        img.math { vertical-align: middle; border-radius: 0; }
        .math-display { text-align: center; margin: 1.6em 0; }
        .math-display-block { display: block; text-align: center; margin: 1.6em 0; }
        .md-image-blocked {
          display: inline-flex; align-items: center; gap: 0.4em;
          color: var(--cola-text-soft); background: var(--cola-bg-soft);
          border: 1px dashed var(--cola-border); border-radius: 6px;
          padding: 0.3em 0.6em; font-size: 0.9em;
        }
        .md-image-blocked svg { width: 1.1em; height: 1.1em; flex: 0 0 auto; }

        /* §4.6 表格: 容器 border-radius 8px + border 1px solid #d8d3ce,
           表头 background #eae6e1 + border-bottom 2px solid #c44b2b + padding 12px 16px,
           单元格 padding 11px 16px + border-bottom 1px solid #d8d3ce,
           斑马纹 tr:nth-child(even) #eae6e1 50%透明,
           hover rgba(196,75,43,0.04),
           font-size 0.95em */
        .table-wrap { overflow-x: auto; margin: 1.6em 0; border: 1px solid var(--cola-border); border-radius: 8px; }
        table { border-collapse: collapse; width: 100%; font-size: 0.95em; letter-spacing: 0.02em; }
        thead th {
          background: var(--cola-bg-soft);
          color: var(--cola-heading);
          font-weight: 700;
          padding: 12px 16px;
          border-bottom: 2px solid var(--cola-accent);
          text-align: left;
        }
        td { padding: 11px 16px; border-bottom: 1px solid var(--cola-border); color: var(--cola-text); }
        tr:last-child td { border-bottom: none; }
        tbody tr:nth-child(even) { background: color-mix(in srgb, var(--cola-bg-soft) 50%, transparent); }
        tbody tr:hover td { background: color-mix(in srgb, var(--cola-accent) 4%, transparent); }

        /* Callouts */
        .callout {
          background: var(--c-bg);
          border-radius: 0;
          margin: 1.6em 0;
          padding: calc(1.22em - (var(--line-height) - 0.78) * 0.5em) 1.24em 1.14em;
        }
        .callout-title { display: flex; align-items: flex-start; gap: 0.3em; font-weight: 600; color: var(--c-accent); }
        .callout-icon { flex: 0 0 auto; display: inline-flex; align-items: center; justify-content: center; height: calc(var(--body-size) * var(--line-height)); }
        .callout-icon svg { width: 1em; height: 1em; transform: translateY(-0.06em); }
        .callout-info .callout-icon, .callout-todo .callout-icon,
        .callout-question .callout-icon, .callout-help .callout-icon, .callout-faq .callout-icon,
        .callout-quote .callout-icon, .callout-cite .callout-icon { padding-top: 0.05em; }
        .callout-warning .callout-icon, .callout-attention .callout-icon,
        .callout-bug .callout-icon { padding-top: 0.06em; }
        .callout-example .callout-icon { padding-top: 0.1em; }
        .callout-success .callout-icon, .callout-check .callout-icon, .callout-done .callout-icon,
        .callout-failure .callout-icon, .callout-fail .callout-icon,
        .callout-missing .callout-icon { padding-top: 0.15em; }
        .callout-title-text { flex: 1 1 auto; }
        .callout-collapsible > summary { cursor: pointer; list-style: none; }
        .callout-collapsible > summary::-webkit-details-marker { display: none; }
        .callout-collapsible > summary::after { content: "›"; flex: 0 0 auto; margin-left: 0.3em; transition: transform 0.15s ease; }
        .callout-collapsible[open] > summary::after { transform: rotate(90deg); }
        .callout-body { margin-top: 0.4em; }
        .callout-body:empty { margin-top: 0; }
        .callout-body > p { margin-bottom: 0.5em; }
        .callout-body > :first-child { margin-top: 0; }
        .callout-body > :last-child { margin-bottom: 0; }
        .callout-body > .callout:last-child { margin-top: 0; }

        /* Scrollbar */
        ::-webkit-scrollbar { width: 6px; height: 6px; }
        ::-webkit-scrollbar-thumb { background: #ccc8c2; border-radius: 3px; }
        ::-webkit-scrollbar-thumb:hover { background: #b5b0aa; }
        ::-webkit-scrollbar-track { background: transparent; }

        @media print {
          html { font-size: 13px; }
          body { padding: 0; background: #fff; color: #000; }
          * { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
          .callout, pre, blockquote, .table-wrap, .math-display,
          .math-display-block { break-inside: avoid; }
          h1, h2, h3, h4, h5, h6 { break-after: avoid; }
          thead { display: table-header-group; }
          pre { background: #f5f5f5; color: #333; border: 1px solid #ddd; }
          thead th { background: #f5f5f5; }
        }
        """
    }

    /// One-Dark syntax palette for the ColaMD Elegant code panel, matching the
    /// spec §5 colors. The Edmund palette (Tomorrow/One-Dark hybrid from
    /// `CodeSyntaxPalette`) is reused where it agrees with the spec; the
    /// handful of token colors that differ (comment gray, function-name blue)
    /// are overridden here so Read mode's code blocks match the design doc
    /// rather than the editor's Edit-mode palette. Plain `pre code` (untokenized)
    /// inherits the panel's foreground.
    private static func colaCodeTokenRules(dark: Bool) -> String {
        // One-Dark palette — same hexes in both appearances because the code
        // panel is always dark (#2c2c2c light / #14110f dark). The `dark`
        // parameter is accepted for symmetry with `codeTokenRules` and in case
        // a future variant wants to differentiate.
        _ = dark
        let palette: [(String, String)] = [
            ("pre code",                          "#e0dcd7"),
            ("pre code .tok-keyword",             "#c678dd"),
            ("pre code .tok-command",             "#c678dd"),
            ("pre code .tok-type",                "#e5c07b"),
            ("pre code .tok-attribute",           "#e06c75"),
            ("pre code .tok-variable",            "#e06c75"),
            ("pre code .tok-value",               "#98c379"),
            ("pre code .tok-number",              "#d19a66"),
            ("pre code .tok-string",              "#98c379"),
            ("pre code .tok-comment",             "#7c7873"),
        ]
        return palette.map { "\($0.0) { color: \($0.1); }" }
            .joined(separator: "\n")
    }

    // MARK: Callout custom properties

    @MainActor
    private static func calloutVars(_ callouts: [String: CalloutStyle], dark: Bool) -> String {
        // De-dup styles shared by aliases: emit one rule block per type key.
        var out = ""
        for type in callouts.keys.sorted() {
            let style = callouts[type]!
            let accent = style.accentHex(dark: dark)
            let border = style.resolvedBorderHex(dark: dark)
            let bg = style.explicitBackgroundHex(dark: dark)
                ?? rgba(accent, alpha: style.backgroundAlpha)
            out += """
            .callout-\(type) {
              --c-accent: \(accent);
              --c-border: \(border);
              --c-bg: \(bg);
              --c-border-width: \(trim(style.borderWidth))px;
              \(borderEdgeRules(style.borderEdges))
            }

            """
        }
        return out
    }

    private static func borderEdgeRules(_ edges: CalloutStyle.Edges) -> String {
        var parts: [String] = []
        if edges.contains(.left)   { parts.append("border-left: var(--c-border-width) solid var(--c-border);") }
        if edges.contains(.top)    { parts.append("border-top: var(--c-border-width) solid var(--c-border);") }
        if edges.contains(.right)  { parts.append("border-right: var(--c-border-width) solid var(--c-border);") }
        if edges.contains(.bottom) { parts.append("border-bottom: var(--c-border-width) solid var(--c-border);") }
        return parts.joined(separator: " ")
    }

    // MARK: Static element rules

    private static let staticRules = """
    * { box-sizing: border-box; }
    html { -webkit-text-size-adjust: 100%; }
    body {
      font-family: var(--body-font);
      font-size: var(--body-size);
      line-height: var(--line-height);
      color: var(--fg);
      background: var(--bg);
      margin: 0;
      padding: 48px 24px;
    }
    .page { max-width: var(--page-max-width); margin: 0 auto; }
    /* Styled-source spacing: paragraphs and blocks get a full line's breathing
       room, so the cadence feels like a clean, readable version of Edit mode
       rather than a collapsed publication layout. */
    p { margin: 0 0 1em; }
    h1, h2, h3, h4, h5, h6 { line-height: 1.25; font-weight: 600; margin: 1.7em 0 0.7em; }
    /* Heading scale mirrors the editor's, which is the source of truth — see the
       `case .heading` arm in EditorTextView+Rendering.swift. Keep the two in step:
       h4-h6 stay at body size there, and h6 carries no dimming, so it carries
       none here either. */
    h1 { font-size: 1.5em; } h2 { font-size: 1.3em; } h3 { font-size: 1.15em; }
    h4 { font-size: 1em; } h5 { font-size: 1em; } h6 { font-size: 1em; }
    :is(h1, h2, h3, h4, h5, h6):first-child { margin-top: 0; }
    a { color: var(--accent); text-decoration: underline; }
    /* Body color, not --code: the editor draws inline code in the body color
       too, and the two views must agree. --code still tints block code. */
    /* Radii are em, not px, so the chip's corners keep their proportion as the
       font-size stepper moves — a fixed 4px reads as square at large sizes. */
    code { font-family: var(--mono-font); font-size: 0.92em; color: var(--fg);
           background: var(--inline-code-bg); padding: 0.1em 0.35em; border-radius: 0.25em; }
    pre { background: var(--code-bg); padding: 12px 14px; border-radius: 0.5em; overflow-x: auto;
          /* tab-size: browsers default to 8; match the common editor convention of 4. */
          tab-size: 4; -moz-tab-size: 4; }
    pre code { color: var(--fg); background: none; padding: 0; font-size: var(--mono-size); }
    /* Copy button: a bare hover-revealed icon, matching Obsidian's read-mode
       treatment. `.code-block-wrap` takes over `pre`'s outer margin so the
       button can be positioned absolutely inside it without moving `pre`. */
    .code-block-wrap { position: relative; margin: 1em 0; }
    .code-block-wrap pre { margin: 0; }
    .code-copy-btn { position: absolute; top: 8px; right: 10px; display: flex; align-items: center;
                      gap: 4px; font-family: var(--mono-font); font-size: 11px; font-weight: 500;
                      color: var(--faint); background: transparent; padding: 3px 6px;
                      border-radius: 5px; text-decoration: none; cursor: pointer; }
    .code-copy-btn:hover { background: rgba(128, 128, 128, 0.16); }
    .code-copy-btn svg { width: 13px; height: 13px; stroke: var(--faint); }
    /* Hidden until the block is hovered, so it never reserves visible space
       at rest. */
    .code-copy-icon { opacity: 0; transition: opacity .15s; }
    .code-block-wrap:hover .code-copy-icon { opacity: 1; }
    /* Dark mode lifts the bar to the marker gray (--rule is nearly invisible
       there); light mode keeps --rule. */
    blockquote { margin: 1em 0; padding: 0.5em 1em; border-left: 3px solid var(--quote-bar); color: var(--faint); }
    /* Without this, the 1em bottom margin on the last <p> inside a blockquote
       creates asymmetric vertical padding — the blockquote looks heavier at the
       bottom than at the top. Reset it so padding alone controls the spacing. */
    blockquote > p:last-child { margin-bottom: 0; }
    /* A nested blockquote that is the last child of its parent blockquote (or
       callout body) would otherwise leave 1em of extra space below itself inside
       the parent's padding. Collapse it. */
    blockquote > blockquote:last-child,
    .callout-body > blockquote:last-child { margin-bottom: 0; }
    hr { border: none; border-top: 1.5px solid var(--hr); margin: 1.6em 0; }
    mark { background: rgba(255, 200, 0, 0.3); color: inherit; padding: 0 0.1em; }
    /* Obsidian #tag: an accent-colored pill. Style only, no navigation. */
    .tag { color: var(--accent);
           background: color-mix(in srgb, var(--accent) 14%, transparent);
           padding: 0.05em 0.5em; border-radius: 0.8em; font-size: 0.88em; white-space: nowrap; }
    /* Whitelisted inline HTML rendered in Read mode (see HTMLRenderer
       sanitizeInlineHTML). <u>/<mark> use the UA underline / the rule above;
       <kbd> matches the editor's inline-key chrome, <sub>/<sup> get the standard
       line-height-safe reset. */
    kbd { font-family: var(--mono-font); font-size: 0.92em; background: var(--code-bg);
          border: 1px solid var(--rule); border-radius: 4px; padding: 0.05em 0.4em; }
    sub, sup { font-size: 0.75em; line-height: 0; position: relative; vertical-align: baseline; }
    sup { top: -0.5em; }
    sub { bottom: -0.25em; }
    /* Footnotes (see HTMLRenderer.renderFootnotesSection): in-text `[^id]` refs
       are plain (undecorated) superscript links; the bottom-of-page list is a
       smaller, dimmer <ol> below its own <hr>, each entry ending in a backref
       arrow to the in-text marker. */
    sup.footnote-ref a { text-decoration: none; }
    hr.footnotes-sep { margin-bottom: 0.8em; }
    ol.footnotes { font-size: 0.85em; color: var(--faint); }
    ol.footnotes li { margin: 0.4em 0; }
    a.footnote-backref { text-decoration: none; margin-left: 0.2em; font-size: 0.9em; line-height: 1; }
    /* Match the editor's list indentation: level-1 text begins at one marker
       slot past the marker (~2.25em), and each nesting level steps in by one
       slot (~1.25em). Same dot at every level, like Edit mode. */
    /* Only direct children of .page and .callout-body get block margin (1em top
       + bottom) and the wider level-1 indent (2.25em). Nested lists inside list
       items stay at 0 margin — otherwise each level compounds to large gaps. */
    ul, ol { margin: 0; padding-left: 1.25em; }
    .page > ul, .page > ol,
    .callout-body > ul, .callout-body > ol { margin: 1.3em 0; padding-left: 2.25em; }
    li > ul, li > ol { margin: 0; }
    ul { list-style-type: disc; }
    /* No inter-item margin: the editor's list paragraph style sets both
       paragraphSpacing and paragraphSpacingBefore to 0 (see listParagraphStyle in
       EditorTextView+ListRendering.swift), so consecutive items there are one
       line pitch apart — same as a wrapped line inside an item. Any margin here
       makes Read mode's lists looser than the text you typed them into; measured,
       0.35em put items 31.5pt apart against the editor's 26.0pt. */
    li { margin: 0; }
    li::marker { color: var(--marker); font-size: 0.85em; }
    /* Numbers read as text, not as a glyph: keep them at the item's own size so
       Read mode matches Edit mode, where the "N." keeps the body font. */
    ol > li::marker { font-size: 1em; }
    li > p { margin: 0; }
    /* Task items: float the checkbox into the marker slot so the label and
       wrapped lines sit at the same content edge as bullet/number text. The
       negative margin-left pulls the checkbox into the list's padding area; the
       nested <ul>/<ol> clears the float so it falls below.
       Lucide checkbox (a tinted <svg>, see HTMLRenderer/LucideIcons): unchecked =
       dim outlined circle (--marker, the editor's tertiaryLabelColor); checked =
       disc filled in the system accent (--check-fill, matching the editor's
       controlAccentColor) with a white check baked into the SVG. `currentColor`
       in the SVG inherits from `color` below. */
    li.task { list-style: none; }
    li.task > .task-check {
      /* Sized a bit larger than 1em so the Lucide circle (r=10 in a 24-box, so it
         underfills) reads as big as the editor's checkbox. margin-left is roughly
         -(width + margin-right) so the task TEXT starts at the content edge,
         lining up with sibling bullet/number text; hand-tuned to -1.45em (a hair
         less negative than the -1.5em that formula gives) so the marker centers
         over the bullet/number column at every nesting level.
         margin-top (0.1em) centers the box on the first text line's cap-height
         center — tuned visually for Iowan Old Style at 16pt / line-height 1.45. A
         font-agnostic fix would measure NSFont.ascender at render time and emit an
         inline margin-top. */
      float: left; width: 1.2em; height: 1.2em; line-height: 0;
      margin-top: 0.1em;
      margin-right: 0.3em;
      margin-left: -1.45em;
    }
    li.task > .task-check svg { display: block; width: 1.2em; height: 1.2em; }
    .task-check--unchecked { color: var(--marker); }
    .task-check--checked { color: var(--check-fill); }
    li.task--checked > p { opacity: 0.45; text-decoration: line-through; }
    li.task > p { display: inline; margin: 0; }
    li.task > ul, li.task > ol { clear: left; }
    /* Contain the checkbox float within its own item. Without this, a task item
       that has no nested list (the float is never cleared by a child ul/ol)
       leaks its float onto the FOLLOWING sibling, shoving that item's bullet/
       number marker to the right — so sibling markers stop lining up. */
    li.task::after { content: ""; display: block; clear: both; }
    .blank-line { height: calc(var(--body-size) * var(--line-height)); }
    /* Tables keep their natural (content-driven) width and scroll horizontally
       inside .table-wrap instead of squeezing columns or forcing cell text to
       wrap — same idiom as `pre`'s overflow-x below. */
    .table-wrap { overflow-x: auto; margin: 1em 0; }
    table { border-collapse: collapse; }
    th, td { border: 1px solid var(--table-border); padding: 6px 10px; }
    thead th { background: var(--code-bg); }
    img { max-width: 100%; }
    img.math { vertical-align: middle; }
    .math-display { text-align: center; margin: 1em 0; }
    /* `$$…$$` embedded in a prose line: same centered block treatment, but as
       a span (it lives inside the paragraph's <p>, where a <div> is invalid). */
    .math-display-block { display: block; text-align: center; margin: 1em 0; }
    /* Stand-in for a plain-http image, which never loads under ATS. */
    .md-image-blocked { display: inline-flex; align-items: center; gap: 0.4em;
                        color: var(--faint); background: var(--code-bg);
                        border: 1px dashed var(--rule); border-radius: 6px;
                        padding: 0.3em 0.6em; font-size: 0.9em; }
    .md-image-blocked svg { width: 1.1em; height: 1.1em; flex: 0 0 auto; }

    /* Callouts: tinted box + colored title; the icon sits as a non-shrinking
       flex child so a long custom title wraps under the title text, never under
       the icon — the layout the TextKit editor can't achieve. */
    /* Outer margin matches the gap between two consecutive <pre> blocks (UA
       stylesheet gives pre { margin: 1em 0 }; collapsing → 1em gap). Using
       the same value here means neighboring callouts look equally spaced. */
    /* Square corners and em padding both track the editor, which fills a square
       rect per layout fragment (they tile into one box) and derives its pads from
       `pointSize`: the rendered top gap is ~1.2em, calloutBottomPad is 1.14em, and
       the text inset is 2pt + quoteMarkerWidth ≈ 1.24em. The editor's right inset
       is narrower (a `tailIndent = -10` artifact, not a design choice), so both
       sides use the left value rather than reproducing a lopsided box.
       Top padding is NOT a flat 1.2em: what the eye reads as the gap runs from the
       box edge to the title's cap-top, and the title's line box adds half-leading
       above the glyph — so a flat 1.2em rendered ~6pt too deep (measured 25.5pt
       against the editor's 19.5pt). Subtracting half the line box's excess over the
       cap height puts the *rendered* gap on the editor's, and keeps it there as the
       line-height stepper moves. The 0.78 stands in for the body face's cap height
       in em; it is a serif-ish average, not a per-font measurement — a font-agnostic
       version would emit the real capHeight/unitsPerEm ratio alongside --body-size.
       The bottom needs no such correction: it is measured box-edge to box-edge. */
    .callout { background: var(--c-bg); border-radius: 0; margin: 1em 0;
               padding: calc(1.22em - (var(--line-height) - 0.78) * 0.5em) 1.24em 1.14em; }
    /* Icon sits at the top so it stays on the first line of a wrapped title; its
       box is exactly one line tall and centers the glyph, so it lines up with the
       first line's text rather than floating above it. */
    .callout-title { display: flex; align-items: flex-start; gap: 0.3em;
                     font-weight: 600; color: var(--c-accent); }
    .callout-icon { flex: 0 0 auto; display: inline-flex; align-items: center; justify-content: center;
                    height: calc(var(--body-size) * var(--line-height)); }
    /* Lucide glyphs sit a touch low against the title's optical (cap-height)
       center; nudge the icon up so it reads as centered with the title text. */
    .callout-icon svg { width: 1em; height: 1em; transform: translateY(-0.06em); }
    /* Per-glyph optical nudge: a few Lucide icons sit high in their 24-box, so
       push them down a hair to read as centered against the title cap-height.
       Aliases share an icon, so they get the same value. */
    .callout-info .callout-icon, .callout-todo .callout-icon,
    .callout-question .callout-icon, .callout-help .callout-icon, .callout-faq .callout-icon,
    .callout-quote .callout-icon, .callout-cite .callout-icon { padding-top: 0.05em; }
    .callout-warning .callout-icon, .callout-attention .callout-icon,
    .callout-bug .callout-icon { padding-top: 0.06em; }
    .callout-example .callout-icon { padding-top: 0.1em; }
    .callout-success .callout-icon, .callout-check .callout-icon, .callout-done .callout-icon,
    .callout-failure .callout-icon, .callout-fail .callout-icon,
    .callout-missing .callout-icon { padding-top: 0.15em; }
    .callout-title-text { flex: 1 1 auto; }
    /* Collapsible callout (`[!type]-`/`+`): a real <details>/<summary>. Hide the
       native disclosure marker and draw our own chevron that rotates on open. */
    .callout-collapsible > summary { cursor: pointer; list-style: none; }
    .callout-collapsible > summary::-webkit-details-marker { display: none; }
    .callout-collapsible > summary::after { content: "›"; flex: 0 0 auto;
        margin-left: 0.3em; transition: transform 0.15s ease; }
    .callout-collapsible[open] > summary::after { transform: rotate(90deg); }
    .callout-body { margin-top: 0.4em; }
    /* A title-only callout still emits an empty body div; collapse its top margin
       so the box doesn't carry the 0.4em title gap as dead space at the bottom. */
    .callout-body:empty { margin-top: 0; }
    /* Reduce paragraph spacing inside callout bodies so nested callouts and
       body text don't sit too far apart. The full 1em bottom margin (from the
       global <p> rule) + the nested callout's 0.5em top margin would give
       1.5em gap — halving the paragraph bottom margin brings it to ~1em. */
    .callout-body > p { margin-bottom: 0.5em; }
    .callout-body > :first-child { margin-top: 0; }
    .callout-body > :last-child { margin-bottom: 0; }
    /* A callout that is the last child of a callout body (e.g. the nested TIP
       inside the NOTE) has its top margin removed so the space above it is
       governed only by the preceding element's bottom margin (0.5em for a <p>
       from .callout-body > p), not the combined margin collapse of 1em. */
    .callout-body > .callout:last-child { margin-top: 0; }

    @media print {
      body { padding: 0; }
      /* QUIRK: WebKit strips background colors when printing by default (it
         follows the user's browser setting), even though WKWebView.createPDF
         keeps them. `print-color-adjust: exact` forces faithful color output
         so callout backgrounds, code blocks, and highlights survive printing. */
      * { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
      .callout, pre, blockquote, .table-wrap, .math-display,
      .math-display-block { break-inside: avoid; }
      h1, h2, h3, h4, h5, h6 { break-after: avoid; }
      thead { display: table-header-group; }
    }
    """

    // MARK: Helpers

    /// A CSS font stack: the (possibly multi-word) macOS family name quoted, then
    /// a system fallback and a generic. WKWebView resolves installed families
    /// (e.g. "Iowan Old Style") by name; the generic guards the rest.
    private static func cssFontStack(_ family: String, generic: String) -> String {
        let trimmed = family.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == "ui-monospace" {
            return "ui-monospace, \(generic)"
        }
        // "system-ui" is a keyword, not a family to quote — used by the Quick
        // Look preset so previews render in the platform UI font.
        if trimmed == "system-ui" {
            return "-apple-system, system-ui, \(generic)"
        }
        return "\"\(trimmed)\", -apple-system, \(generic)"
    }

    /// Resolves a (possibly dynamic/catalog) `NSColor` for the given appearance
    /// to a CSS `rgba(...)`, preserving alpha. Used so list markers use the exact
    /// same dim as the editor (`NSColor.tertiaryLabelColor`) and can't drift.
    ///
    /// QUIRK: dynamic system colors like `tertiaryLabelColor` store a catalog
    /// reference, not actual RGBA components — calling `usingColorSpace(.sRGB)`
    /// on one outside a drawing context resolves to nil or returns the wrong
    /// variant. `performAsCurrentDrawingAppearance` sets the appearance context
    /// so the catalog resolves to the correct light or dark concrete color.
    @MainActor
    private static func resolvedRGBA(_ color: NSColor, dark: Bool) -> String {
        var resolved = color
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        guard let c = resolved.usingColorSpace(.sRGB) else {
            return dark ? "rgba(235,235,245,0.25)" : "rgba(60,60,67,0.3)"
        }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return "rgba(\(r), \(g), \(b), \(trim(c.alphaComponent)))"
    }

    /// rgba(...) from a "#RRGGBB" hex and an alpha.
    private static func rgba(_ hex: String, alpha: CGFloat) -> String {
        guard let (r, g, b) = rgbComponents(hex) else { return hex }
        return "rgba(\(r), \(g), \(b), \(trim(alpha)))"
    }

    private static func rgbComponents(_ hex: String) -> (Int, Int, Int)? {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let rgb = UInt64(h, radix: 16) else { return nil }
        return (Int((rgb >> 16) & 0xFF), Int((rgb >> 8) & 0xFF), Int(rgb & 0xFF))
    }

    /// Formats a CGFloat without a trailing ".0" so CSS reads cleanly.
    private static func trim(_ v: CGFloat) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%g", v)
    }
}
