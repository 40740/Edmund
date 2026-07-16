import AppKit

// MARK: - Window menu

@MainActor
enum WindowMenu {

    /// The top-level "Window" menu item (with its submenu). Setting this as
    /// `NSApplication.windowsMenu` makes AppKit auto-populate the open-window
    /// list and checkmark the key window below the static items.
    static func build() -> NSMenuItem {
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")

        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")

        windowMenu.addItem(withTitle: "Zoom",
                           action: #selector(NSWindow.performZoom(_:)),
                           keyEquivalent: "")

        windowMenu.addItem(.separator())

        windowMenu.addItem(withTitle: "Bring All to Front",
                           action: #selector(NSApplication.arrangeInFront(_:)),
                           keyEquivalent: "")

        windowMenuItem.submenu = windowMenu
        return windowMenuItem
    }
}
