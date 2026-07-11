# Changelog

All notable changes will be documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

GFM pass: closing the gaps between Edmund and the GFM spec in both edit and read mode.

### Added
- Setext headings (`Title` underlined by `===`/`---`) render in edit mode
- Indented code blocks (4 spaces or a tab, after a blank line) render in edit mode
- HTML `<!-- comments -->`: dimmed in edit mode, hidden in read mode (previously showed as literal text in read mode)
- `<small>` added to the rendered HTML whitelist (both modes)
- `<img src alt width height>` renders the image in both modes, at its declared size (one dimension alone scales proportionally); remote/local image policy applies as for markdown images
- Autolinks ([GFM extension](https://github.github.com/gfm/#autolinks-extension-)): bare `www.…`, `http(s)://…`, and email addresses become links in both modes, with CMD+click to follow
- Inline styling (bold, code, links, ==marks==, …) now renders inside table cells in edit mode; column widths align on the *styled* text, not the raw source
- Inline styling inside headings keeps the heading's font size (`# **bold** and `code``), for ATX and setext headings

### Changed
- A `---` line directly under a paragraph is now a setext h2 underline per GFM, no longer a thematic break — put a blank line between the paragraph and `---` to keep the rule
- `==highlight==` now follows GFM-style flanking: content can't begin or end with whitespace (`== spaced ==` stays literal)
- Setext heading content spans the whole preceding paragraph run (`Foo\nbar\n---` is one h2), matching GFM Example 51
- Interior blank lines stay inside an indented code block (GFM Examples 82/87)

### Fixed
- Tables whose delimiter row cell count differs from the header are no longer parsed as tables in edit mode (GFM Example 203)
- Backslash-escaped pipes (`\|`) are cell content, not column separators (GFM Example 200)
- The ATX heading closing sequence (`# foo ###`) hides like other delimiters instead of showing in the heading (GFM 4.2)
- A newline inserted at a display-math block boundary no longer leaves a stray centered line (separator newlines now reset when adjacent blocks restyle)

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
