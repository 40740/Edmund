# Changelog

All notable changes will be documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.2] - 2026-08-11

Rewrote the ColaMD Read-mode CSS to faithfully transcribe the ColaMD reference implementation (`themes/elegant.css`) instead of the embellished version I shipped in 3.0.0/3.0.1. The earlier releases added decorative elements the reference never had (hr center dot, link underline animation, table outer border + zebra striping, oversized paddings) and got several values wrong. This release strips all of that back.

### Fixed
- **Heading underline removed** — h1/h2 now have only `padding-bottom` (spacing), no `border-bottom`. The reference CSS ships no drawn underline; the spec's "带下划线" describes the padding gap, not a line.
- **hr simplified** — plain `border-top: 1px solid #d8d3ce`, no gradient, no center dot. The dot was a design-doc aspiration the reference CSS never shipped.
- **Link hover simplified** — `text-decoration: underline` on hover, no `background-size` animation. Matches the reference exactly.
- **Inline code padding** — `2px 6px` (was `3px 8px`), `border-radius: 3px` (was `4px`). Reference values.
- **Code block padding** — `18px 22px` (was `20px 24px`), `border-radius: 6px` (was `8px`), `line-height: 1.6` (was `1.65`), `margin: 1.5em` (was `1.6em`). Reference values.
- **Blockquote padding** — `15px 20px 15px 25px` (was `16px 22px 16px 26px`), no `border-radius` (was `0 6px 6px 0`). Reference values.
- **Mark padding** — `1px 4px` (was `3px 8px`), `border-radius: 2px` (was `4px`), `color: var(--cola-text)` (was `inherit`). No `box-decoration-break`. Reference values.
- **Table** — removed outer container border + `border-radius: 8px`, removed zebra striping (`tr:nth-child(even)`). Only the header background, 2px terracotta header underline, cell bottom borders, and hover tint remain — exactly what the reference ships.
- **List line-height** — `1.8` (was `1.85`). Reference value.
- **Scrollbar thumb** — `#ccc8c2` (was `var(--cola-border)`), hover `#b5b0aa`. Reference values.
- **blockquote color** — uses `var(--cola-text-soft)` which is `#555` in light / `#a89f96` in dark (the reference uses `#444`, but `--cola-text-soft` is the spec's token for this tier).

### Changed
- Every ColaMD CSS rule now carries a comment citing either "reference CSS" (the shipped `elegant.css`) or "spec §X" (the design doc), so the source of each value is auditable.

## [3.0.1] - 2026-08-11

Bug-fix release for the ColaMD Elegant preset. v3.0.0 only themed Read mode (CSS); Edit mode — the native NSTextView — still rendered with Edmund's colors. All 7 user-reported bugs stemmed from this.

### Fixed
- **Bold text not red (Edit mode)** — bold now paints in the terracotta accent (`#c44b2b` / `#e0653f`), matching the design doc. Edmund preset unchanged (bold stays body ink).
- **Blockquote bar not red, no background (Edit mode)** — the quote bar is now 4pt terracotta (was 2pt gray), and the quote box carries a soft paper-tint background (`#eae6e1` / `#26231f`). Quote text uses a warm gray (`#555` / `#a89f96`).
- **Inline code + highlight colors (Edit mode)** — inline code now uses the warm-paper chip (`#e8e4df` / `#2a2622`) with terracotta text; highlight uses the 15% terracotta tint instead of default yellow.
- **Code block panel (Edit mode)** — fenced code blocks now use the dark panel (`#2c2c2c` / `#14110f`) with warm off-white text (`#e0dcd7`) in both appearances, matching the spec's "technical counterpoint" to the serif body.
- **Table borders (Edit mode)** — table chrome now uses the warm border (`#d8d3ce` / `#3a342e`) instead of the system separator gray.
- **Heading color (Edit mode)** — headings now paint in a deeper ink (`#1a1a1a` / `#e0dcd7`), one step darker than the body.
- **Top padding (Read mode)** — Read-mode body padding reduced from 48px to 30px (matching the spec's `#write` padding), eliminating the blank space at the top.
- **Heading underline (Read mode)** — h1's underline is now 2px terracotta (`#c44b2b`) instead of 1px gray, so it reads as an accent anchor.

### Added
- `EditorTextView+PresetColors.swift` — a single extension providing preset-aware alternatives for every rendering color that differs between Edmund and ColaMD (bold, inline code, highlight, blockquote bar/background/text, code block background/text, table border/header, heading color). Each property returns the ColaMD value when `theme.preset == .colaElegant` and falls through to the historical Edmund value otherwise.
- `DecoratedTextLayoutFragment.tableBorderColor` — the border color is now captured at fragment-vend time (on the main actor) so the nonisolated `draw` path doesn't touch the main-actor-isolated `theme` property.

## [3.0.0] - 2026-08-11

The first release with **selectable theme presets**. Edmund ships two looks now: the original Edmund theme (unchanged) and a brand-new **ColaMD Elegant** port. Pick one in Settings ▸ Appearance ▸ Theme; the editor, Read mode, PDF export, and print output all flip together.

### Added
- **Theme presets** — a new "Theme:" picker in Settings ▸ Appearance. Two presets ship:
  - **Edmund** (default): the original blue-accent-on-white look, byte-for-byte unchanged.
  - **ColaMD Elegant** (new): a port of [ColaMD's `elegant.css`](https://github.com/marswaveai/ColaMD/blob/main/themes/elegant.css) — warm-paper background (`#f0edea` light / `#1c1a18` dark), terracotta accent (`#c44b2b` / `#e0653f`), serif body (Songti SC by default, with a JetBrains Mono / Menlo code stack), 0.04em letter-spacing, 1.9 line-height, 4px terracotta blockquote bar, dark code panel with 20/24px breathing room, terracotta-tinted tables, and One-Dark syntax highlighting.
- New `ThemePreset` enum in `EdmundCore/Model/ThemePreset.swift`; `EditorTheme` carries a `preset` field that `HTMLTheme.css`, `HTMLTheme.backgroundColor`, and `EditorTextView.editorBackgroundColor` all route on.
- A complete ColaMD stylesheet in `HTMLTheme.colaElegantCSS`, ported from the design spec — independent of the Edmund CSS path so neither look can drift into the other.
- `AppSettings.themePreset` (UserDefaults key `settings.appearance.themePreset`) and an `EditorThemePreset` key on the theme itself; both are kept in sync on launch.
- `ThemePresetTests` covering palette tokens, typography, blockquote/code/table/mark/hr rules, dark-mode variants, One-Dark syntax palette, and a regression guard that the Edmund path is untouched.

### Changed
- Bumped `CFBundleShortVersionString` to `3.0.0` and `CFBundleVersion` to `11`. The major-version bump reflects the new theme system as a user-visible feature set, not a breaking API change.

## [Unreleased]

### Added
- The editor scrolls half a screen past the last line, so the line you are writing is never stuck at the bottom edge of the window (with Typewriter Scroll on, its own centering space covers this).

### Fixed
- Typewriter Scroll now centers the caret on every line, including the first and last ones and in documents shorter than the window — it reserves half a viewport of space at each end while the mode is on.

## [0.4.1] - 2026-08-01

### Fixed
- Min window width was too wide (temp fix)

## [0.4.0] - 2026-08-01

Fixed table misalignment (#251). Added Settings > Extensions and Advanced Math extension. Various UI improvements. 

### Added
- Settings > General > Manage Version History...
- Settings > Extensions
- Advanced Math extension via [RaTeX](https://ratex.lites.dev)

### Changed
- Read mode styling now better aligns with edit mode (header size, line height, callout color and padding)
- Removed document change settings from Settings > General to follow AppKit conventions
- Removed redundant configs from Settings > Edit and reworded some settings

### Fixed
- Table misalignment #251
- Table text alignment in edit mode
- Auto-hide toolbar now works
- Open Recent now populates
- Edmund now actually creates backups when auto-save is off
- Finder services


## [0.3.0] - 2026-07-27

Settings stuff. 

Thanks to @CaliLuke for his first contribution (#236) and for being the first community contributor :D

### Added
- Improved performance (#236 @CaliLuke)
- **(Almost) Full Obsidian-flavored Markdown support**: YAML front matter, `[image|dimension()` (implicit), `^block`, `#tag`, collapsible callout
- **Find and replace** in Apple Notes fashion
- **Settings > Edit**: Hide toolbar, focus mode, detect indentation, show invisible characters, show line numbers, hard-wrap long lines
- **Settings > Syntax**: Toggle Markdown syntax support, add code block syntax
- **Settings > Key Bindings**
- Edit > Find, Spelling & Grammar, Transformations, Speech menus
- Finder services
- `Option+Cmd+I` to open inspector

### Changed
- Misc UI improvements: Numbered lists marker in read mode, thicker thematic break, removed bottom border from edit mode tables, removed inline code color from read mode
- Dark mode readability: Empty checkbox in edit mode, blockquote bars in read mode, table borders in edit mode
- Code block syntax highlighting is now controlled by syntax-based JSON instead of general regex
- Inline math block renders as block in read mode
- Format > Comments now wraps selection in `<!-- selection -->`

### Fixed
- Headers don't render spaces after `#...`
- Indented code block renders as monospace
- Replaced right-click "Font" menu in edit mode with our custom Format > Font menu


## [0.2.1] - 2026-07-17

### Added
- Window menu
- Code block copy button in read mode

### Changed
- Code blocks are now styled by default, similar to blockquotes / callouts
- Math blocks inline are now rendered as a block, instead of inline in `\displaystyle`
- Switching between edit and read mode now preserves viewport
- Lighter background color in dark mode to reduce contrast

### Fixed
- `$$...$$` was not rendering verbatim
- External images glitching and freezing the app
- Switching from read to edit mode waits for edit mode to fully load


## [0.2.0] - 2026-07-13

Full GFM support per the [specs](https://github.github.com/gfm/). Existing implementations better respect GFM specs where applicable. Automatic renumbering of numbered lists. Various editor UX improvements. 

### Added
- GFM elements
  - Setext headings (`Title` underlined by `===`/`---`) render in edit mode
  - Autolinks: bare `www.…`, `http(s)://…`, and email addresses become real links in both modes
  - Indented code blocks
  - HTML elements except for ones [officially disallowed](https://github.github.com/gfm/#disallowed-raw-html-extension-)
  - Reference links
  - Block quote lazy continuation
- Nested styling
  - Headings support all inline styling (not just math)
  - Nested block quote in edit mode
  - Tables support inline styling in edit mode
- Automatic renumbering for numbered list

### Changed
- A `---` line directly under a paragraph is now a setext h2 underline
- Heading delimiter always shows when user is typing on the heading line
- `==highlight==` now follows GFM-style flanking: content can't begin or end with whitespace (`== spaced ==` stays literal)
- Tables rows now have separators
- List continuation no longer adds extra `-` or `- [ ]` if user creates the corresponding list right before the corresponding delimiter. E.g., `- hi |(Enter here)- bye` no longer creates extra `-`.

### Fixed
- Security issues found by GitHub code scanning
- Block quote bar too tall
- Tables
  - Delimiter row cell count differs from the header are not tables in edit mode (GFM Example 203)
  - Backslash-escaped pipes (`\|`) are cell content
  - Content overflow wraps out of cell in edit mode
- ATX heading closing sequence (`# foo ###`) hides
- Newline inserted at a display-math block boundary leaves a stray centered line

## [0.1.4] - 2026-07-09

Various small fixes and improvement and new round of grind at the [delete caret drift](https://github.com/I7T5/Edmund/issues/156). I think it actually worked this time, but don't quote me on it. 

### Added
- `CMD+=`, `CMD+-`, and `CMD+0` to zoom in/out/reset. Also in View menu
- External images rendering in editor
- Block external images setting in Settings > Advanced 

### Changed
- Rename "Source Mode" to "Show Source in Editor" in app and button menu. Removed icon from button menu. 
- Opening an existing file closes the last opened Untitled window with no edit history
- Move Automatic updates to Settings > General
- Apply Settings > Appearance > Max content width to read mode 

### Fixed
- Images have extra bottom padding when editor is not in full screen
- Images do not resize with max content width if the user changes the setting when the app is open
- Tables overflow handled by horizontal scroll
- Callouts have an extra line at the bottom when they are the last element of a file
- Footnotes rendering in edit mode and linking between inline marker and content in read mode
- Math environments `\begin{}...\end{}` padding offset in edit mode
- Math environments `\begin{}...\end{}` rendering in read mode
- Delete caret drift, round 7 ([docs](docs/delete-drift-investigation.md)) [#156](https://github.com/I7T5/Edmund/issues/156)

---

## [0.1.3] — 2026-07-04

### Fixed
- Delete caret drift *with reproduction* ([docs](docs/investigations/delete-drift-investigation.md)) [#156](https://github.com/I7T5/Edmund/issues/156)

---

## [0.1.2] — 2026-07-03

Polishing the editor and trying to have Fable 5 fix all the big bugs while I still have it with me. 

### Changed
- Redo now jumps to where changed text was instead of caret
- Removed old code for identity mapping, etc., using [ponytail](https://github.com/DietrichGebert/ponytail)-review

### Fixed
- Updater [#158](https://github.com/I7T5/Edmund/issues/158)
- Icon display for callouts with custom titles ([docs](docs/investigations/archives/callout-title-wrap-investigation.md))
- Undo/redo viewport glitches from TextKit 2 ([docs](docs/investigations/viewport-glitch-investigation.md))
- Delete caret drift ([docs](docs/investigations/delete-drift-investigation.md)) [#156](https://github.com/I7T5/Edmund/issues/156)

---

## [0.1.1] — 2026-06-29

### Added
- Thematic Break `---`/`***` in the Format menu
- Remember window size: new document windows reopen at the size of the last one.

### Changed
- Max content width is now an absolute physical width (cm / in) with a max-width cap and a cm/in unit toggle. 
- Typewriter Mode renamed to Typewriter Scroll

### Fixed
- Typewriter Scroll no longer jumps the viewport when you click to reposition the caret — it re-centers only while typing.

---

## [0.1.0] — 2026-06-27

First public release.

- **Live WYSIWYG preview** — Typora/Obsidian style
- **GFM support** — bold, italic, strikethrough, tables, task lists, fenced code with syntax highlighting, blockquotes, alerts
- **Extended syntax** — ==highlights==, [[WikiLinks]], `[^footnotes]`, Obsidian-flavored callouts and comments
- **Math** — inline (`$…$`) and display (`$$…$$`) rendering via SwiftMath
- **Native macOS UI** — AppKit editor, SwiftUI settings panel, full Dark Mode support
- **Keyboard-first** — configurable shortcuts, no required mouse interaction
- **Auto-update** — Sparkle 2.x with EdDSA-signed appcast; checks on launch
- **Open source** — Apache 2.0
