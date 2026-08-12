# Changelog

All notable changes will be documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [5.17.0] - 2026-08-12

### Fixed
- **截图 / 微信截图粘贴仍空白**：上一版加固了 PNG 重编码失败的兜底，但用户实测微信截图 / 部分系统截图仍空白。根因是这些工具把图片注册在**私有 UTI** 上，`pasteboard.data(forType:)` 对常见的 `.png/.tiff/.public.jpeg/.public.image` 都取不到数据，导致 `pasteImageIfPresent` 判定“没有图”，最终回退到默认粘贴渲染成空白。修复：新增 `NSImage(pasteboard:)` 兜底检测与重编码（图片检测与取数都加这一最后手段），任何 AppKit 能解码的剪贴板图片都会被保存并插入 `![](...)`，不再静默空白。
- **未保存文档粘贴图片被“请先保存”挡住**：此前在未保存的新文档里粘贴图片只会弹「请先保存文档」，用户保存后仍需再粘贴一次，体验割裂。修复：现在粘贴图片时会**自动保存文档**（新文档弹标准保存面板），保存完成后**自动重试粘贴**，一步到位、图片不丢。
- **按错键的提示音**：按到未绑定任何命令的按键组合时，AppKit 会把它路由到 `noop:` 并由 `NSTextView` 播报警音（“按错键”的哔声）。修复：`doCommand(by:)` 直接吞掉 `noop:`，未绑定按键不再哔声，所有真实编辑命令不受影响。

### 秒开 / 轻量化保证
- 所有改动只在“粘贴那一刻”或“按键那一刻”触发，不引入定时器 / 监听 / 索引 / 网络 / 常驻资源，完全不碰打开 / 保存路径。

## [5.16.0] - 2026-08-12

### Fixed
- **工具栏「Customize Toolbar…」仍然不能拖拽 / 替换 / 增删按钮**：上版只给按钮设了 `minSize/maxSize`，但 macOS 的自定义视图（`view`）toolbar item 在 Customize Toolbar 面板里**还必须有 `image` 才能被拖拽**——只有 `view` 时面板里的条目是「不可拖动的占位」。修复：给每个 `NSToolbarItem`（24 个格式按钮 + 侧边栏 + 视图模式）都补设 `item.image`（与按钮一致的 SF Symbol），面板中即可正常拖拽 / 替换 / 增删。
- **截图 / 微信截图粘贴仍空白**：加固图片粘贴路径，杜绝任何静默空白——
  - 若剪贴板带图但 `NSImage` 解码失败，只要原始字节是合法 PNG/JPEG，仍会原样保存并插入 `![](...)`，不再因解码失败而丢弃；
  - PNG 重编码失败时改为直接保存原始图片字节（用正确的 jpg/png 后缀），不再静默空白；
  - 所有无法处理的图片粘贴都会弹出明确提示（请先保存 / 无法粘贴图片 / 无法保存图片），**绝不回退到会渲染成空白的默认粘贴**。

### 秒开 / 轻量化保证
- 工具栏只是给 item 多设一个 `image`（复用已创建的 SF Symbol），无常驻开销；粘贴加固仍只在粘贴那一刻触发，不碰打开 / 保存路径。
- 不引入定时器 / 监听 / 索引 / 网络 / 常驻资源。

## [5.15.0] - 2026-08-12

### Fixed
- **工具栏「Customize Toolbar…」无法拖拽 / 替换 / 增删按钮**：根因是自定义工具栏按钮（`NSButton`）没有明确尺寸，macOS 把尺寸为 0×0 的自定义视图 toolbar item 视为不可拖动，导致 Customize Toolbar 面板里能看到按钮却拖不到常驻工具栏上，常驻工具栏也无法删减/增加。修复：新增 `configureToolbarButtonSize`，给每个按钮 `sizeToFit()` + 最小尺寸（26×22），并给每个 `NSToolbarItem` 设置与按钮一致的 `minSize`/`maxSize`。现在面板和常驻工具栏的每一项都有真实尺寸，拖拽 / 替换 / 增删全部恢复可用。
- **截图粘贴仍空白**：若剪贴板确实带图但落不了盘（文档未保存 / 写盘失败），旧逻辑会回退到 `super.paste`——NSTextView 把图片当 `NSTextAttachment` 插入，markdown 编辑器渲染成空白占位。现在：新增 `pasteboardContainsImage` 多类型兜底检测（PNG/TIFF/JPEG/public.image/图片文件 URL）；一旦确实是图但无法落盘，不再回退到会变空白的默认粘贴，而是弹明确提示（未保存 →「请先保存文档」；写盘失败 →「无法保存图片」），绝不静默粘贴空白。

### Added
- **轻量版图片拖拽缩放**：编辑模式鼠标悬停在已渲染的图片上，图片右下角出现一个 16×16 的缩放手柄；按住拖动即可按比例调整图片宽度（高度等比），松开把新尺寸写回 Markdown 源（转为 `<img src="…" width="N" height="N">` 标签，阅读模式 / 导出 PDF 已支持）。双击可恢复原始尺寸（重新手动输入或删除 width/height）。

### 秒开 / 轻量化保证
- 图片缩放是事件驱动（hover 才显示手柄、按住拖才计算），平时零定时器 / 零监听 / 零常驻资源。
- 写回只在鼠标抬起那一刻发生一次，走现有 `applyFormattingEdit` 编辑管线（可撤销）。
- 工具栏尺寸只是给已创建按钮设个 frame，无常驻开销。
- 不引入任何定时器 / 监听 / 后台线程 / 网络。

## [5.14.0] - 2026-08-12

### Fixed
- **粘贴图片不再失效 / 粘贴为空**：修复系统截图（⌃⌘⇧4）和微信截图复制后 ⌘V 粘贴图片没触发或粘贴为空的 Bug。根因是剪贴板除了图片数据外，往往还附带一个 `.string`（空字符串或 promised-file 路径），旧逻辑先读文本把它误判成「纯文本粘贴」。现在**图片检测提前到最前面**——先看剪贴板有没有 PNG/TIFF 图片数据，有就粘贴图片；纯文本分支忽略空字符串；并直接读 `pasteboard.data(forType:)` 拿图片字节（不再依赖偶发拿不到图的 `NSImage(pasteboard:)`）。另加兜底：若文档还没保存到磁盘会弹提示「请先保存文档」，避免图片被静默丢弃。

### Added
- **工具栏全面可自定义**：把**几乎全部格式命令（24 个）注册进工具栏的 Customize Toolbar… 自定义库**——粗体、斜体、下划线、删除线、高亮、行内代码、代码块、行内公式、公式块、键盘键、注释、Wiki链接、链接、图片、脚注、标题、项目符号列表、编号列表、待办列表、引用块、分割线、表格、Callout、清除格式。默认工具栏仍保留原来的 6 个常用按钮，其余都在自定义库里，你拖哪个上来就显示哪个。

### 秒开 / 轻量化保证
- 只改编辑路径（粘贴、工具栏自定义库），完全不碰打开 / 保存路径。
- 自定义库只是 24 个 `FormatSpec` 结构体（几百字节、静态初始化一次），**只有真正被拖上工具栏的按钮才在 `itemForItemIdentifier` 里懒加载成 `NSButton`**，不用的永远不创建——零常驻开销。
- 不引入定时器 / 监听 / 索引 / 网络 / 常驻资源。

## [5.13.0] - 2026-08-12

### Added
- **拖放图片 / 文件直接插入引用**：把截图或文件直接拖进编辑器窗口，自动在光标处生成 Markdown 引用——拖**图片**（png/jpg/gif/svg/webp/heic…）插入 `![](相对路径)`（自动算好相对当前文档的路径）；拖 `.md` 或其它文件插入 `[文件名](路径)` 链接；拖纯文本原样插入。
- **粘贴图片自动存盘 + 插入引用**：从剪贴板粘贴一张图片（截图 / 复制的图）时，自动把它以 PNG 写入**文档同目录的 `images/`** 文件夹，并在光标处插入 `![](./images/paste-xxx.png)`。
- **工具栏常用格式按钮**：窗口工具栏新增 6 个图标按钮——**粗体、斜体、代码、标题(H1)、链接、项目符号列表**，点击即对选中文本生效（复用现有格式命令，`target: nil` 沿响应链路由到聚焦编辑器）。

### 秒开 / 轻量化保证
- 只改编辑路径（拖放 / 粘贴 / 工具栏点击），完全不碰打开 / 保存路径。
- 拖放与粘贴图片只在动作发生的**那一刻**同步处理一次；工具栏按钮是纯 UI、点击才触发对应命令。
- 不引入定时器 / 监听 / 索引 / 网络 / 常驻资源，零常驻开销。

## [5.12.0] - 2026-08-12

### Added
- **「清除格式」现在能清除块级标记**：选中标题 / 引用块 / 列表（含待办）里的任意文字，一键清除会把**整行**的块级标记也剥掉——大标题 `#`、引用 `>`、列表 `-` / `*` / `+` / `1.`、待办 `- [ ]` 等全部清成普通段落；支持嵌套/叠加（如 `> # 引言` → 一次清成纯文本）。
- **右键菜单一级入口**：编辑区右键菜单的一级菜单里新增「清除格式」项（位于「全选」分隔线之后），不用再进顶部「格式」菜单；因已注册进 `formattingActions`，阅读模式下自动置灰。

### Changed
- **外部粘贴改为纯文本**：修复从浏览器 / 其它 App 复制长文本粘贴卡十几秒的问题。根因是 `NSTextView` 默认 `paste` 会读取剪贴板最富格式（HTML/RTF/RTFD）并做昂贵的富文本转换，而 Edmund 每次编辑都会 `recomposeDirty` 重新着色、丢弃这些富属性——纯属白做功。现在 `paste` 只读取剪贴板纯文本（`.string`），走正常编辑管线一次性插入，外部粘贴秒贴不再卡。仅当剪贴板无纯文本表示（如纯图片）时才回退默认路径。

### 秒开 / 轻量化保证
- 只改清除格式与粘贴两条编辑路径，完全不碰打开 / 保存路径。
- 清除格式 O(选中行数)，纯本地字符串处理；粘贴反而更快（省掉最昂贵的富文本转换）。
- 不引入定时器 / 监听 / 常驻资源，零常驻开销。

## [5.11.0] - 2026-08-12

### Added
- **编辑模式「清除格式」命令**：在格式菜单的醒目位置（分隔线之后）新增「清除格式」。选中一段文本后点击，一键剥离其中所有内联 Markdown 格式标记，只保留纯文本。支持混合 / 相邻 / 嵌套格式（如 `***nested***` → `nested`），未成对的孤立标记（如 `a * b`、`** unmatched`）保留不动。

  | 标记 | 示例 | 结果 |
  |---|---|---|
  | 粗体 | `**bold**` / `__bold__` | `bold` |
  | 斜体 | `*italic*` / `_italic_` | `italic` |
  | 代码 | `` `code` `` | `code` |
  | 高亮 | `==highlight==` | `highlight` |
  | 删除线 | `~~strike~~` | `strike` |
  | 下划线 | `<u>underline</u>` | `underline` |
  | 键盘 | `<kbd>key</kbd>` | `key` |
  | 公式 | `$math$` | `math` |
  | Wiki 链接 | `[[page]]` | `page` |
  | 链接 | `[text](url)` | `text` |
  | 图片 | `![alt](img.png)` | `alt` |
  | 注释 | `<!-- comment -->` | `comment` |

### 秒开 / 轻量化保证
- 只在**选中文本**上做一次性处理，不碰打开文件路径；固定几组非回溯正则、最多 4 轮，O(选中长度)，与现有格式命令同量级。
- 不引入任何定时器 / 监听 / 常驻资源，菜单命令点一下即完成，零常驻开销。
- 走现有 `applyFormattingEdit` 单步撤销，与其它格式命令一致。
- 阅读模式下该命令自动置灰；打开文件秒开不受任何影响。

## [5.10.0] - 2026-08-12

### Changed
- **左侧文件侧边栏默认不开启**：移除“打开文件自动显示侧边栏”的逻辑。全新启动 / 打开文档默认就是全屏，和该功能出现前完全一致；仅当你通过工具栏按钮或视图菜单主动展开时才显示。
- **右上角工具栏新增侧边栏开关**：在“视图模式”旁新增 `sidebar.left` 按钮，点击展开 / 收起左侧文件侧边栏。按钮高亮（accent 色）= 已展开，灰色 = 收起；点开侧边栏里的文件仍走原有秒开路径，换文件后自动指向新目录。视图 ▸ 侧边栏 菜单仍可用（同一开关）。

### Added
- **大纲加背景（Liquid Glass）+ 字体放大**：大纲展开面板背后新增系统 `NSVisualEffectView`（`.sidebar` material + 圆角），轻量半透明背景，长文档行不再从下方透出与大纲文字叠加；大纲条目字号 12pt → **14pt**、行高 20 → 24，更易读。

### 轻量化保证
- 打开文件不碰秒开路径（默认侧边栏关，打开即原全屏）。
- 侧边栏列目录仅点开后异步后台做，关闭时零 IO。
- 大纲背景 `NSVisualEffectView` 由系统 GPU 硬件加速，仅展开时活动、收起即停。
- 大纲解析仍仅 hover 时扫一次 O(行数)。

## [5.9.0] - 2026-08-12

### Added
- **左侧边栏文件浏览器**：打开一个文件后，侧边栏自动显示该文件所在文件夹里所有 Edmund 能打开的格式（`.md`/`.markdown`/`.mdown`/`.mkd` + 常见纯文本），文件夹在前、文件在后、按名排序；能一层层展开子文件夹（点开才懒加载，海量目录也不卡）；点击文件走与现有完全相同的 `openDocument` 打开路径，秒开不变。通过 **视图 ▸ 侧边栏** 开关，首次打开文件自动显示，手动开关后尊重你的选择。
- **右侧悬浮大纲目录 TOC**：平时只是一条 16pt 透明热区、零绘制零资源；鼠标划过右边缘才滑出大纲。列出 `#`～`######` 标题并按层级缩进（H1 不缩、H2 缩 14pt…），H1/H2 加粗；点击标题直接滚动定位到对应内容；移开鼠标自动收起。

### 秒开 / 轻量化保证
- 打开文件不碰秒开路径（仍是原原生打开流程）；侧边栏列目录在打开完成后再异步后台做，绝不卡在打开那一刻。
- 子文件夹按需懒加载；大纲仅 hover 显示时做一次 O(行数) 标题扫描，隐藏时零开销；点击跳转复用现有滚动能力。

## [5.8.2] - 2026-08-11

### Fixed
- 编辑模式代码块复制按钮位置：根因是 `renderedRect(forBlock:)` 用代码块首行（开 fence 行 ```）的 typographicBounds 计算矩形宽度，fence 行只有三个字符、glyph 范围很窄（约 24pt），按钮右对齐到该窄矩形就落到了面板左上角。现改为按文本容器完整宽度计算，按钮固定贴在代码块**右上角**。
- 代码块插入体验：空行无选中插入时默认只有一行空内容、光标直接落在内容行，打字即第一行代码，无语言标签飘到右上角；选中多行包裹后光标也落在第一行内容。
- 引用块文字垂直居中：`opticalNudge` 从 1.5pt 提升到 3.0pt，中文衬线字体墨迹重心偏移补偿更足，文字不再视觉偏下、真正光学居中。

## [5.8] - 2026-08-11

### Fixed
- 编辑模式代码块圆角：手绘贝塞尔圆角改用标准 kappa 控制点（0.5523·r），之前把控制点放在圆弧端点上会把圆角往外顶成凸起的“钩子”，现在与阅读模式 CSS 的圆润胶囊一致。
- 表格底部间距增大：最后一行的下边距从单元格内边距 1 倍提升到 1.5 倍，闭合表格不再紧贴下方段落。
- 字体与主题联动：在设置里自定义标准字体后，即使启用优雅/新闻纸等带专属衬线字体的主题，用户选择的字体也保持生效，不再被主题默认字体覆盖、也不再出现“切主题字体被重置”的现象；主题字体仅在用户未自定义时作为默认。

## [5.7] - 2026-08-11

### Fixed
- 表格完全闭合：表头行增加顶边框线，之前表格上方没有线、盒子不封闭；每行底线内收 0.5pt 绘制，之前下行斑马纹填充会盖住非斑马行的底线（表现为"行线消失"）；斑马纹不再向下越过底线（之前填充向下多延伸了 verticalPad，看起来像阴影越界）。
- 表格网格线改用主题色（优雅主题的 #d8d3ce 暖灰），默认的 `separatorColor` 太浅在白色背景上几乎看不见，表现为"行线都消失了"。
- 引用块文字垂直居中改为按真实墨迹测量：把引用首行渲染成小位图、扫描笔画实际起止位置来设置首行行高，任意字号/字体下顶部与底部内边距都相等（之前按字形包围盒估算，中文衬线字体的字形盒与真实笔画有偏差，内边距随字号变化且方向会翻转）。

## [5.6] - 2026-08-11

### Fixed
- 编辑模式斜体真正渲染出来：根因是中文无衬线字体（宋体/苹方）没有斜体字面，`NSFontManager` 找不到斜体时就静默返回原字体，导致 `*斜体*` 和 `<i>` 在编辑模式永远显示为正体（阅读模式 WebKit 会自动合成斜体，两边不一致）。现在对没有斜体字面的字体用 12° 斜切矩阵合成斜体（CoreText 矩阵字体，TextKit 2 原生渲染），中文斜体与阅读模式一致。
- 编辑模式引用块多行之间不再出现 15pt 空隙：根因是首行的 topPad 通过向上扩展 fragment 帧实现，TextKit 绘制时会把后续每一行都往下推同样高度，行与行之间裂开一条白缝。现改为抬高首行最小行高，行与行正常紧贴、面板与红条连续闭合。
- 编辑模式行内代码 / 高亮胶囊的位置修正：`enumerateTextSegments` 返回的是容器坐标，而绘制上下文是 fragment 本地坐标，胶囊整体偏下一行高并被渲染表面裁掉，裸段落里的 `` `code` `` 和 `==mark==` 胶囊一直画不出来。现按 fragment 原点换算坐标，胶囊精确落在文字后面（并扩展渲染表面防止内边距被裁）。

## [5.5] - 2026-08-11

### Fixed
- 编辑模式下引用块文字真正垂直居中：根因是 TextKit 渲染表面未覆盖引用块顶部内边距（仅覆盖文字行以上），导致顶部内边距被裁剪掉、视觉上只剩底部内边距、文字偏下。现按完整框体范围（含上下内边距）绘制，上下内边距恢复对称、文字居中。
- 编辑模式下 `<i>/<em>/<b>/<strong>/<del>/<s>/<strike>/<code>` 行内 HTML 标签不再显示为源码，而是与对应 markdown 语法一致地渲染（斜体/加粗/删除线/行内代码胶囊），与 Read 模式的 GFM 原生渲染保持一致。

## [5.3] - 2026-08-11

### Fixed
- 编辑模式下普通段落中的 `==高亮==`、行内代码、`<kbd>` 恢复胶囊背景色：裸段落此前走了普通文本 fragment 不绘制胶囊，现已统一走装饰绘制路径
- 编辑模式下引用块文字垂直居中：修掉了单行引用块被文本末尾空行撑出多余下内边距的问题
- Read 模式 `<kbd>` 不再黑底黑字看不清：背景改为与编辑模式一致的浅色胶囊，并显式指定可读的墨色

## [5.1] - 2026-08-11

- 引用块:红色竖条加粗为 4pt 并贯穿整个引用面板(上下对齐、居中),面板上下内边距保持一致
- 表格:修复超长单元格换行后最后一行被吃掉一半的问题(补齐行高并纳入渲染边界)
- 行内代码:加大背景色内边距,角更圆润,不显得拥挤
- ==高亮标记==:改为带内边距的圆角胶囊底色(原来是紧贴文字的方底)
- 代码块:消除各代码行之间的拼接细横线,保持一整块纯背景色面板

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
