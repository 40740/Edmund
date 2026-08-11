import AppKit

// MARK: - Window menu

@MainActor
enum WindowMenu {

    /// The top-level "Window" menu item (with its submenu). Setting this as
    /// `NSApplication.windowsMenu` makes AppKit auto-populate the open-window
    /// list and checkmark the key window below the static items.
    static func build() -> NSMenuItem {
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")

        windowMenu.addItem(withTitle: "最小化",
                           action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")

        windowMenu.addItem(withTitle: "缩放",
                           action: #selector(NSWindow.performZoom(_:)),
                           keyEquivalent: "")

        windowMenu.addItem(.separator())

        windowMenu.addItem(withTitle: "全部置于顶层",
                           action: #selector(NSApplication.arrangeInFront(_:)),
                           keyEquivalent: "")

        windowMenuItem.submenu = windowMenu
        return windowMenuItem
    }
}
