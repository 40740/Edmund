# Changelog

All notable changes will be documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.0] - 2026-08-11

### Fixed
- **代码块连续面板**: 代码块行间距从 body 继承的 `lineSpacing` 改为独立的 `minimumLineHeight/maximumLineHeight` 固定行高 + `lineSpacing: 0`，消除行间间隙，使代码块渲染为连续的圆角面板而非一行一行断裂
- **代码块文字重叠**: 代码块段落样式设置 `paragraphSpacing=0`，避免 TextKit 2 分发的段落间距导致代码块与相邻普通文本重叠
- **代码块面板颜色对齐 ColaMD**: 默认浅色 `#f6f8fa`、深色 `#161b22`（与 ColaMD `--code-block-bg` 一致）
- **代码块语法高亮跟随面板**: `prefersDarkCodeTheme` 现在跟随代码面板颜色（Elegant 的深色面板始终用深色语法高亮），而非窗口外观
- **代码块面板文字色**: 新增 `codeBlockTextColor` 属性，Elegant 预设使用 `#e0dcd7` 暖色文字于深色面板上
- **代码块重置字间距**: 代码块和代码段显式设置 `kern: 0`，不受正文字间距影响
- **正文字间距**: `baseAttributes` 添加 `kern` 属性（Elegant 0.18 / 其他 0.12），改善中文和衬线体的可读性
- **引用块独立排版**: `blockquoteParagraphStyle` 使用独立的 `minimumLineHeight/maximumLineHeight` 和 `lineSpacing: 0`，不再继承 body 的 lineSpacing，解决嵌套引用视觉碰撞
- **浅色/深色主题切换完整**: `applyTheme` 现在同步更新 `backgroundColor`、`insertionPointColor`、`selectedTextAttributes`，并始终 `invalidateLayout`，修复主题/预设切换后半生效的问题
- **bodyParagraphStyle 稳定性**: 用显式的 `minimumLineHeight/maximumLineHeight`（=fontSize+lineSpacing）替代 `lineSpacing`，防止 TextKit 2 在相邻块使用自定义段落样式时压缩行高

## [0.5.9] - 2026-08-11

### Fixed
- **行内代码背景颜色空间修复**: 将 `NSColor(calibratedWhite:...)` 改为 `NSColor(srgbRed:...)`，修复浅色/深色模式下行内代码灰色背景几乎不可见的问题（calibrated 色彩空间在相同数值下比 sRGB 明显更浅）
- **行内代码内边距增大**: 左右内边距 6→8pt，上下内边距 3→4pt
- **代码块垂直内边距增大**: 默认值 16→20pt
- **引用块外边距滑块拆分**: 将单一「引用块上下外边距」拆分为独立的「上外边距」和「下外边距」滑块，支持非对称调节，保留旧版键值向后兼容
- **高亮内边距滑块拆分**: 将单一「高亮内边距」拆分为「左右内边距」和「上下内边距」两个独立滑块，支持动态配置
- **列表行距增大**: 行距倍数默认值 1.8→2.0，滑块范围扩展至 1.0–3.0

## [0.5.8] - 2026-08-11

### Fixed
- **读模式（预览）现在实时响应设置变化**: 此前拖动「外观 ▸ 细节样式」滑块后预览纹丝不动，只在文档编辑、切换明暗或手动刷新时才重新渲染——`HTMLTheme` 注释声称会监听 `UserDefaults` 但代码里根本没有观察者。现在 `ReadModeWebView` 监听 `UserDefaults.didChangeNotification`，任一主题相关 key（10 个细节滑块 + Cola 主题预设 + 明暗模式 + 内容宽度）变化即即时重渲染，且保留滚动位置。
- **编辑模式行内代码背景真正可见**: 浅色模式下背景原来是 10–14% 透明度的浅灰（≈#EDEDED，对白底几乎不显色，看起来就是"没有背景"），现提到 20%（≈#E6E6E6），深色模式提到 40%，对齐 ColaMD 参考主题 #e8e4df 的可见灰芯片观感。

## [0.5.7] - 2026-08-10

### Fixed
- **真正接通细节样式滑块到编辑渲染**: 0.5.6 仅在设置 UI / Read 模式写入了部分 UserDefaults，编辑模式 `DetailStyleKey` 与 `detailStyleSettingsDidChange` 未监听新键，拖动无效
- 行内代码灰色背景对比度提高（浅色 alpha 0.14 / 深色 0.28），并新增「行内代码上下内边距」滑块（默认 3pt）
- `==高亮==` / `<mark>` 改为可内边距的圆角芯片绘制（与行内代码同路径），新增「高亮内边距」滑块（默认 4pt）
- 引用块「上下外边距」滑块现写入 `paragraphSpacingBefore` + `paragraphSpacing`，上下对称
- 列表「列表行距」滑块接入 `listParagraphStyle`（默认 1.8 倍）
- 代码块「上下内边距」接入面板 `topPad`/`bottomPad`
- Read 模式 CSS 同步：高亮内边距、行内代码上下内边距、列表行高

## [0.5.6] - 2026-08-10

### Fixed
- 行内代码(单反引号)恢复灰色底:浅色模式默认底色改为 `#eaeaea`,与 ColaMD 一致;左右内边距接上「行内代码左右内边距」滑块(默认 6pt),不再压字
- 代码块(高亮)内边距改为动态:新增「代码块上下内边距」滑块(默认 16pt),与已有的左右内边距、圆角滑块一起实时生效
- 引用块新增「引用块上下外边距」滑块(默认 16pt),上下外边距一起设置更平衡;内边距仍由「引用块上下边距」控制
- 列表项行距新增「列表行距」滑块(默认 1.8 倍),比正文更松,对齐 ColaMD
- 「设置 ▸ 外观 ▸ 细节样式」的全部滑块现在真正写入并即时重渲染(此前 Read 模式未读取这些 UserDefaults,滑块虽然显示却无效)

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
