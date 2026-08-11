# Changelog

All notable changes will be documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.5.3] - 2026-08-11

- 修复 v0.5.5.2 编译错误:ColaThemePreset.displayName 的 switch 缺少闭合括号导致整个 enum 解析失败
- 此修复使「优雅 Plus」主题能正常编译发布

(修复前 v0.5.5.2 因编译错误无法发布,请使用 v0.5.5.3)


## [0.5.5.2] - 2026-08-11

- 新增「优雅 Plus」主题(设置▸外观):基于 ColaMD 优雅主题,字间距加大至 0.04em,中英文更舒展
- 修复 Edit 模式字间距不生效:baseAttributes 新增 .kern 属性,TextKit 原生渲染字间距(Elegant Plus 0.04em @ 16pt = 0.64pt)
- 修复引用块上下边距不对称:blockquoteParagraphStyle 新增 paragraphSpacingBefore = quoteVPad,首行顶部留白与底部一致
- 行内代码背景色:优雅 Plus 主题使用 #e8e4df 浅纸色底,Edit 模式 drawInlineCodeChips 正常绘制
- 高亮(mark)内边距与背景:优雅 Plus 使用赤陶红淡色 rgba(196,75,43,0.15)
- 代码块内边距:Read 模式 pre padding 18px 22px
- 键盘按键 kbd 拟物风格、表格单元格内边距加大

注意:此前 v0.5.5.1 仅修改了 Read 模式(HTMLTheme),Edit 模式(平时所见)未改动。本次 v0.5.5.2 同时修复 Edit 模式与 Read 模式。


## [0.5.5.1] - 2026-08-11

- 字间距加大:ColaMD 优雅主题正文 letter-spacing 设为 0.03em,中英文均有呼吸感
- 代码块内边距加大:pre padding 从 12px 14px 提升至 18px 22px,代码不再紧贴深色面板边缘
- 行内代码内边距加大:padding 从 0.1em 0.35em 提升至 0.15em 0.4em
- 高亮(mark)内边距加大:padding 从 0 0.1em 提升至 0.15em 0.4em 并加圆角;优雅主题高亮背景改用赤陶红淡色 rgba(196,75,43,0.15)
- 引用块上下内边距一致:padding 改为 0.85em 1.2em 0.85em 1.4em(上下对称),引用条加粗至 4px,右侧加圆角
- 键盘按键 kbd 拟物风格:底部 2px 边框 + 阴影 + 圆角 5px
- 表格单元格内边距加大:从 6px 10px 提升至 8px 14px


## [0.5.5] - 2026-08-10

- 修复标题下划线消失:绘制区域被 TextKit 裁剪,现已扩展;线距文字 6pt 且不再压住下一行文字
- 修复引用块上边距:顶部的 15pt 内边距同样被裁剪,现已完整显示(上下一致)
- 新增「设置 ▸ 外观 ▸ 细节样式」:标题下划线距离、引用块上下边距、行内代码左右内边距、代码块圆角、代码块左右内边距 5 个滑块,拖动即时生效,无需重启

## [0.5.4] - 2026-08-10

- 标题下划线与文字拉开距离(6pt)
- 代码块修复为整块圆角面板(不再每行一个圆角矩形),左右内边距加大到 16pt
- 行内代码改为带内边距(2px 6px)和圆角的胶囊底色,对齐 ColaMD 数值
- 引用块上下内边距加大到 15pt(ColaMD `padding: 15px 20px 15px 25px`)
- 右键菜单全中文(编辑/阅读/在编辑器中显示源码、剪切/复制/粘贴/全选/字体)
- 代码块复制按钮改为浅色底+深色字,在深色代码块上清晰可见

## [0.5.3] - 2026-08-10

- 完整复刻 ColaMD 优雅主题:代码块深色背景+圆角、行内代码底色与内边距、加粗/引用红色、标题下划线、列表点黑色、表格红粗表头线+完全闭合+对齐的斑马纹、单元格内边距加大
- 编辑模式代码块悬停复制按钮
- Read 模式复制按钮升级为 ColaMD 风格(图标+文字+已复制反馈)
- 顶部空白修复:文档首行紧贴顶部,无预留空白带

## [0.5.2] - 2026-08-10

### Fixed
- **No more blank band above the first line**: the typewriter scroll top overscroll
  is gone, so every document opens flush at the top regardless of the typewriter
  setting (previously half a viewport was reserved, which read as a bug).
- **Theme preset now actually applies**: the settings picker wrote one
  UserDefaults key while `EditorTheme.load` read another, so the chosen preset
  silently stayed on System. Unified on a single key.
- **Table edges closed**: left and right borders drawn, so every column is boxed
  like GitHub.

### Added
- **Full ColaMD theme fidelity**: bold text and inline code render in Elegant's
  accent red, blockquotes get the red bar + soft paper fill + muted text, and
  table headers carry the 2px red rule; h1/h2 get ColaMD's hairline underline.
  Applied in both the editor and Read mode.
- **Code-block copy button, ColaMD style**: the Read-mode button is now a
  labeled "复制" pill that flashes "已复制 ✓"; the editor (Edit mode) gained a
  hover copy button on fenced code blocks that copies the code without fences.
- **Chinese UI**: menu bar, Settings panes, About window, toolbar, version
  history, and key-binding conflict messages are translated to Chinese.

## [0.5.1] - 2026-08-10

### Fixed
- **Theme preset key mismatch** (see 0.5.2 — first shipped here).
- **Table edges closed** (see 0.5.2 — first shipped here).

### Added
- **Chinese UI** (see 0.5.2 — first shipped here).
- **Typewriter scroll defaults to off** so documents open without the top blank.

## [0.5.0] - 2026-08-10

### Added
- **ColaMD themes** (Settings ▸ Appearance ▸ Theme): four presets ported from ColaMD — Light, Dark, Elegant (warm paper + Chinese serif) and Newsprint (PT Serif-style paper) — each forcing its own palette in the editor and in Read mode. System keeps the old behaviour.
- **GitHub-style tables**: zebra striping on alternating data rows, bold header, and tabular numerals — in both the editor and Read mode.
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
