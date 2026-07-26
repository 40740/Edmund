import AppKit
import EdmundCore

// MARK: - View menu

@MainActor
enum ViewMenu {

    /// The top-level "View" menu item (with its submenu).
    static func build() -> NSMenuItem {
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")

        // Routes through the responder chain to the key window's Document, which
        // flips the persisted setting and retitles this item Show/Hide in
        // validateMenuItem — so it always agrees with Settings ▸ Edit ▸ Display.
        // (AppKit's own toggleToolbarShown(_:) would move the toolbar behind the
        // setting's back.) The title here is the first-launch default; the real
        // one is applied every time the menu opens.
        viewMenu.addItem(withTitle: "Hide Toolbar",
                         action: #selector(Document.toggleToolbarShown(_:)),
                         keyEquivalent: "")

        // Routes through the responder chain to the key window's toolbar.
        // AppKit auto-inserts "Show Tab Bar"/"Show All Tabs" above this at
        // runtime (window tabbing is on by default) — that position isn't
        // ours to control short of disabling tabbing outright.
        viewMenu.addItem(withTitle: "Customize Toolbar…",
                         action: #selector(NSWindow.runToolbarCustomizationPalette(_:)),
                         keyEquivalent: "")
        viewMenu.addItem(.separator())

        let typewriterItem = viewMenu.addItem(
            withTitle: "Typewriter Scroll",
            action: #selector(AppDelegate.toggleTypewriterMode(_:)),
            keyEquivalent: "")
        typewriterItem.state = AppDelegate.typewriterModeEnabled() ? .on : .off

        // Dims everything but the lines the selection touches. Same setting as
        // Settings ▸ Edit ▸ Editor, so the two always agree.
        let focusItem = viewMenu.addItem(
            withTitle: "Focus Mode",
            action: #selector(AppDelegate.toggleFocusMode(_:)),
            keyEquivalent: "")
        focusItem.state = AppSettings.focusMode ? .on : .off

        // View-mode toggle (Edit ↔ Read) + the Source-mode checkbox.
        viewMenu.addItem(.separator())
        viewMenu.addItem(FormatMenu.viewModeToggleItem())
        viewMenu.addItem(withTitle: "Show Source in Editor",
                         action: #selector(Document.toggleSourceMode(_:)),
                         keyEquivalent: "")

        // Web Inspector (⌥⌘I). nil target → routes through the responder chain
        // to the key window's Document, so it works from Edit mode too: it
        // switches to Read mode and opens the inspector, and toggles the
        // inspector back off when it's already up.
        let inspectItem = viewMenu.addItem(withTitle: "Inspect Reader",
                         action: #selector(Document.toggleReaderInspector(_:)),
                         keyEquivalent: "i")
        inspectItem.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(.separator())

        // Zoom (font size + max content width, scaled together). Target nil
        // routes through the responder chain to the key window's Document.
        // Kept last, directly above the separator AppKit inserts before its
        // automatic "Enter/Exit Full Screen" item at the menu's end.
        viewMenu.addItem(withTitle: "Actual Size",
                         action: #selector(Document.actualSize(_:)),
                         keyEquivalent: "0")
        viewMenu.addItem(withTitle: "Zoom In",
                         action: #selector(Document.zoomIn(_:)),
                         keyEquivalent: "=")
        viewMenu.addItem(withTitle: "Zoom Out",
                         action: #selector(Document.zoomOut(_:)),
                         keyEquivalent: "-")
        viewMenu.addItem(.separator())

        viewMenuItem.submenu = viewMenu
        return viewMenuItem
    }
}
