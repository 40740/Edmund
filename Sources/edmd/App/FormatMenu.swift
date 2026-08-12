import AppKit
import EdmundCore

// MARK: - Format menu (declarative command registry)
//
// The Format menu and its shortcuts are described by a single table of
// `MenuCommand`s and built from it. Action methods live on `EditorTextView`
// (and `Document` for the view-mode cycle); items use a nil target so they
// route through the responder chain to the focused editor — exactly like the
// undo/redo items in `setupMenuBar`.
//
// User-configurable shortcuts: every command carries a stable `id`, a `group`
// (the menu it appears under) and a default `Shortcut`. `makeItem()` resolves a
// per-`id` override from `KeyBindingStore` and registers the built item in
// `KeyBindingCatalog`, which is what Settings ▸ Key Bindings lists and edits.

/// A key equivalent: the (lowercased) key plus its modifier flags.
struct Shortcut: Equatable {
    let key: String
    let modifiers: NSEvent.ModifierFlags

    static func cmd(_ key: String) -> Shortcut { Shortcut(key: key, modifiers: [.command]) }
    static func cmdShift(_ key: String) -> Shortcut { Shortcut(key: key, modifiers: [.command, .shift]) }
    static func cmdOpt(_ key: String) -> Shortcut { Shortcut(key: key, modifiers: [.command, .option]) }
}

/// One actionable menu command.
struct MenuCommand {
    let id: String
    /// The menu this command lives under, as Settings ▸ Key Bindings groups it.
    var group: String = "格式"
    /// The submenu it sits in, if any ("Font", "Heading", …). Settings lists the
    /// commands nested under this title, the way the menu bar shows them.
    var submenu: String? = nil
    let title: String
    let action: Selector
    /// The out-of-the-box shortcut. The user's override, if any, wins in `makeItem()`.
    var shortcut: Shortcut? = nil
    var tag: Int = 0
    var representedObject: Any? = nil

    @MainActor func makeItem() -> NSMenuItem {
        let effective = KeyBindingStore.effective(id: id, default: shortcut)
        let item = NSMenuItem(title: title, action: action, keyEquivalent: effective?.key ?? "")
        item.keyEquivalentModifierMask = effective?.modifiers ?? []
        item.tag = tag
        item.representedObject = representedObject
        KeyBindingCatalog.shared.register(id: id, group: group, submenu: submenu, title: title,
                                          defaultShortcut: shortcut, item: item)
        // nil target → responder chain (focused EditorTextView / Document).
        return item
    }
}

@MainActor
enum FormatMenu {

    /// The top-level "Format" menu item (with its submenu).
    static func build() -> NSMenuItem {
        let formatItem = NSMenuItem()
        let menu = NSMenu(title: "格式")

        menu.addItem(headingSubmenuItem())
        menu.addItem(thematicBreakCommand.makeItem())
        menu.addItem(.separator())
        menu.addItem(clearFormattingCommand.makeItem())
        menu.addItem(.separator())

        for cmd in listCommands { menu.addItem(cmd.makeItem()) }
        menu.addItem(.separator())

        for cmd in linkCommands { menu.addItem(cmd.makeItem()) }
        menu.addItem(.separator())

        for cmd in blockCommands { menu.addItem(cmd.makeItem()) }
        menu.addItem(calloutSubmenuItem())
        menu.addItem(footnoteCommand.makeItem())
        menu.addItem(.separator())

        menu.addItem(fontSubmenuItem())

        formatItem.submenu = menu
        return formatItem
    }

    /// The "Toggle View Mode" item (⌘E) for the View menu — bracketed by
    /// dividers by the caller.
    static func viewModeToggleItem() -> NSMenuItem {
        MenuCommand(id: "view.toggleMode", group: "视图", title: "切换视图模式",
                    action: #selector(Document.toggleViewMode(_:)),
                    shortcut: .cmd("e")).makeItem()
    }

    // MARK: - Groups

    private static let listCommands: [MenuCommand] = [
        MenuCommand(id: "format.bulletedList", title: "项目符号列表",
                    action: #selector(EditorTextView.formatBulletedList(_:)), shortcut: .cmdOpt("b")),
        MenuCommand(id: "format.numberedList", title: "编号列表",
                    action: #selector(EditorTextView.formatNumberedList(_:))),
        MenuCommand(id: "format.checklist", title: "任务清单",
                    action: #selector(EditorTextView.formatChecklist(_:)), shortcut: .cmd("l")),
    ]

    private static let linkCommands: [MenuCommand] = [
        MenuCommand(id: "format.link", title: "链接",
                    action: #selector(EditorTextView.formatLink(_:)), shortcut: .cmd("k")),
        MenuCommand(id: "format.wikilink", title: "Wiki 链接",
                    action: #selector(EditorTextView.formatWikilink(_:))),
        MenuCommand(id: "format.image", title: "图片",
                    action: #selector(EditorTextView.formatImage(_:))),
    ]

    private static let thematicBreakCommand = MenuCommand(id: "format.thematicBreak", title: "分隔线",
                    action: #selector(EditorTextView.formatThematicBreak(_:)))

    /// Clear all inline Markdown formatting on the selection, leaving plain text.
    /// Selection-scoped and cheap, so it fits the秒开/轻量化 contract.
    private static let clearFormattingCommand = MenuCommand(id: "format.clearFormatting", title: "清除格式",
                    action: #selector(EditorTextView.clearFormatting(_:)))

    private static let footnoteCommand = MenuCommand(id: "format.footnote", title: "脚注",
                    action: #selector(EditorTextView.formatFootnote(_:)))

    private static let blockCommands: [MenuCommand] = [
        MenuCommand(id: "format.table", title: "表格",
                    action: #selector(EditorTextView.formatTable(_:))),
        MenuCommand(id: "format.codeBlock", title: "代码块",
                    action: #selector(EditorTextView.formatCodeBlock(_:))),
        MenuCommand(id: "format.mathBlock", title: "公式块",
                    action: #selector(EditorTextView.formatMathBlock(_:))),
        MenuCommand(id: "format.blockQuote", title: "引用块",
                    action: #selector(EditorTextView.formatBlockQuote(_:)), shortcut: .cmdShift("b")),
    ]

    private static let fontCommands: [MenuCommand] = [
        MenuCommand(id: "format.bold", submenu: "字体", title: "粗体",
                    action: #selector(EditorTextView.formatBold(_:)), shortcut: .cmd("b")),
        MenuCommand(id: "format.italic", submenu: "字体", title: "斜体",
                    action: #selector(EditorTextView.formatItalic(_:)), shortcut: .cmd("i")),
        MenuCommand(id: "format.underline", submenu: "字体", title: "下划线",
                    action: #selector(EditorTextView.formatUnderline(_:)), shortcut: .cmd("u")),
        MenuCommand(id: "format.strikethrough", submenu: "字体", title: "删除线",
                    action: #selector(EditorTextView.formatStrikethrough(_:))),
        MenuCommand(id: "format.highlight", submenu: "字体", title: "高亮",
                    action: #selector(EditorTextView.formatHighlight(_:))),
        MenuCommand(id: "format.code", submenu: "字体", title: "代码",
                    action: #selector(EditorTextView.formatCode(_:))),
        MenuCommand(id: "format.math", submenu: "字体", title: "公式",
                    action: #selector(EditorTextView.formatInlineMath(_:))),
        MenuCommand(id: "format.keyboard", submenu: "字体", title: "键盘按键",
                    action: #selector(EditorTextView.formatKeyboard(_:))),
        MenuCommand(id: "format.comment", submenu: "字体", title: "注释",
                    action: #selector(EditorTextView.formatComment(_:))),
    ]

    /// GitHub alert types (uppercase in source: `> [!NOTE]`).
    private static let githubCalloutTypes = ["NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"]

    /// Obsidian-only callout types (lowercase). note/tip/warning are omitted
    /// since they duplicate NOTE/TIP/WARNING already in the GitHub group.
    private static let obsidianCalloutTypes = [
        "abstract", "info", "todo", "success", "question",
        "failure", "danger", "bug", "example", "quote",
    ]

    // MARK: - Submenus

    private static func headingSubmenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "标题", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "标题")
        for level in 1...6 {
            menu.addItem(MenuCommand(id: "format.heading\(level)", submenu: "标题",
                                     title: "标题 \(level)",
                                     action: #selector(EditorTextView.formatHeading(_:)),
                                     tag: level).makeItem())
        }
        item.submenu = menu
        return item
    }

    private static func calloutSubmenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "提示 / 标注", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "提示 / 标注")
        for type in githubCalloutTypes {
            menu.addItem(MenuCommand(id: "format.callout.\(type)", submenu: "提示 / 标注",
                                     title: type.capitalized,
                                     action: #selector(EditorTextView.formatCallout(_:)),
                                     representedObject: type).makeItem())
        }
        menu.addItem(.separator())
        for type in obsidianCalloutTypes {
            menu.addItem(MenuCommand(id: "format.callout.\(type)", submenu: "提示 / 标注",
                                     title: type.capitalized,
                                     action: #selector(EditorTextView.formatCallout(_:)),
                                     representedObject: type).makeItem())
        }
        item.submenu = menu
        return item
    }

    private static func fontSubmenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "字体", action: nil, keyEquivalent: "")
        item.submenu = fontMenu()
        return item
    }

    /// A fresh Font submenu built from `fontCommands` (Bold, Italic, …). Also
    /// used to replace the system Font submenu in the editor's right-click menu
    /// (see `EditorTextView.contextFontMenuProvider`).
    static func fontMenu() -> NSMenu {
        let menu = NSMenu(title: "字体")
        for cmd in fontCommands { menu.addItem(cmd.makeItem()) }
        return menu
    }
}
