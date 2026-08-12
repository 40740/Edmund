import AppKit
import EdmundCore

// MARK: - View menu

@MainActor
enum ViewMenu {

    /// The top-level "View" menu item (with its submenu).
    static func build() -> NSMenuItem {
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "视图")

        // Routes through the responder chain to the key window's Document, which
        // flips the persisted setting and retitles this item Show/Hide in
        // validateMenuItem — so it always agrees with Settings ▸ Edit ▸ Display.
        // (AppKit's own toggleToolbarShown(_:) would move the toolbar behind the
        // setting's back.) The title here is the first-launch default; the real
        // one is applied every time the menu opens.
        viewMenu.addItem(MenuCommand(id: "view.toggleToolbar", group: "视图", title: "隐藏工具栏",
                                     action: #selector(Document.toggleToolbarShown(_:))).makeItem())

        // Full-screen auto-hide. Lives here rather than in Settings, next to
        // the switch it qualifies.
        viewMenu.addItem(MenuCommand(id: "view.autoHideToolbar", group: "视图",
                                     title: autoHideToolbarTitle,
                                     action: #selector(Document.toggleAutoHideToolbar(_:))).makeItem())

        // Routes through the responder chain to the key window's toolbar.
        // AppKit auto-inserts "Show Tab Bar"/"Show All Tabs" above this at
        // runtime (window tabbing is on by default) — that position isn't
        // ours to control short of disabling tabbing outright.
        viewMenu.addItem(withTitle: "自定义工具栏…",
                         action: #selector(NSWindow.runToolbarCustomizationPalette(_:)),
                         keyEquivalent: "")
        viewMenu.addItem(.separator())

        let typewriterItem = MenuCommand(id: "view.typewriterScroll", group: "视图",
                                         title: "打字机滚动",
                                         action: #selector(AppDelegate.toggleTypewriterMode(_:))).makeItem()
        typewriterItem.state = AppDelegate.typewriterModeEnabled() ? .on : .off
        viewMenu.addItem(typewriterItem)

        // Dims everything but the lines the selection touches. Same setting as
        // Settings ▸ Edit ▸ Editor, so the two always agree.
        let focusItem = MenuCommand(id: "view.focusMode", group: "视图", title: "专注模式",
                                    action: #selector(AppDelegate.toggleFocusMode(_:))).makeItem()
        focusItem.state = AppSettings.focusMode ? .on : .off
        viewMenu.addItem(focusItem)

        // Left file sidebar. Target nil routes through the responder chain to the
        // key window's Document, which flips the persisted setting and re-lays out.
        let sidebarItem = MenuCommand(id: "view.sidebar", group: "视图", title: "侧边栏",
                                      action: #selector(Document.toggleSidebar(_:))).makeItem()
        sidebarItem.state = AppSettings.sidebarVisible ? .on : .off
        viewMenu.addItem(sidebarItem)

        // View-mode toggle (Edit ↔ Read) + the Source-mode checkbox.
        viewMenu.addItem(.separator())
        viewMenu.addItem(FormatMenu.viewModeToggleItem())
        viewMenu.addItem(MenuCommand(id: "view.sourceMode", group: "视图",
                                     title: "在编辑器中显示源码",
                                     action: #selector(Document.toggleSourceMode(_:))).makeItem())

        // Web Inspector (⌥⌘I). nil target → routes through the responder chain
        // to the key window's Document, so it works from Edit mode too: it
        // switches to Read mode and opens the inspector, and toggles the
        // inspector back off when it's already up.
        viewMenu.addItem(MenuCommand(id: "view.inspectReader", group: "视图", title: "检查阅读视图",
                                     action: #selector(Document.toggleReaderInspector(_:)),
                                     shortcut: .cmdOpt("i")).makeItem())
        viewMenu.addItem(.separator())

        // Zoom (font size + max content width, scaled together). Target nil
        // routes through the responder chain to the key window's Document.
        // Kept last, directly above the separator AppKit inserts before its
        // automatic "Enter/Exit Full Screen" item at the menu's end.
        for cmd in zoomCommands { viewMenu.addItem(cmd.makeItem()) }
        viewMenu.addItem(.separator())

        viewMenuItem.submenu = viewMenu
        return viewMenuItem
    }

    /// Title case, like every other menu item. Only in the View menu — the
    /// toolbar's own context menu is AppKit's (Icon and Text / … / Customize
    /// Toolbar…) and Apple's apps put this setting in View, the way Safari
    /// carries "Always Show Toolbar in Full Screen".
    static let autoHideToolbarTitle = "自动隐藏工具栏"

    private static let zoomCommands: [MenuCommand] = [
        MenuCommand(id: "view.actualSize", group: "视图", title: "实际大小",
                    action: #selector(Document.actualSize(_:)), shortcut: .cmd("0")),
        MenuCommand(id: "view.zoomIn", group: "视图", title: "放大",
                    action: #selector(Document.zoomIn(_:)), shortcut: .cmd("=")),
        MenuCommand(id: "view.zoomOut", group: "视图", title: "缩小",
                    action: #selector(Document.zoomOut(_:)), shortcut: .cmd("-")),
    ]
}
