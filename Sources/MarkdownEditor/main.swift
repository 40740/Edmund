import AppKit
import MarkdownEditorCore

// --- App Delegate -----------------------------------------------------------

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()

        let windowWidth: CGFloat = 400
        let windowHeight: CGFloat = 500

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        window.minSize = NSSize(width: 320, height: 400)

        // Match window background to editor — adapts to dark mode automatically
        window.backgroundColor = NSColor.textBackgroundColor

        // Empty toolbar gives the titlebar extra height (roomy traffic lights,
        // like iTerm minimal). The .unified style keeps it compact.
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        // Build the text system chain:
        //   NSTextStorage → NSLayoutManager → NSTextContainer → NSTextView
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let contentSize = NSSize(width: windowWidth, height: CGFloat.greatestFiniteMagnitude)
        let textContainer = NSTextContainer(size: contentSize)
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let editor = EditorTextView(
            frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            textContainer: textContainer
        )
        editor.minSize = NSSize(width: 0, height: 0)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        // Top padding clears the transparent titlebar + toolbar area
        editor.textContainerInset = NSSize(width: 24, height: 52)

        let scrollView = NSScrollView(frame: window.contentView!.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.documentView = editor

        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Menu Bar
    //
    // macOS dispatches Cmd+C/V/X/A/Z through the Edit menu's key equivalents.
    // Without a menu bar, these shortcuts silently do nothing.  We create a
    // minimal menu bar with the standard Edit menu items wired to the first
    // responder's standard actions (copy:, paste:, cut:, selectAll:, undo:, redo:).

    @MainActor private func setupMenuBar() {
        let mainMenu = NSMenu()

        // App menu (required for Cmd+Q)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit md",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu (required for Cmd+C/V/X/A/Z)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")

        editMenu.addItem(withTitle: "Undo",
                         action: Selector(("undo:")),
                         keyEquivalent: "z")

        let redoItem = editMenu.addItem(withTitle: "Redo",
                                        action: Selector(("redo:")),
                                        keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]

        editMenu.addItem(NSMenuItem.separator())

        editMenu.addItem(withTitle: "Cut",
                         action: #selector(NSText.cut(_:)),
                         keyEquivalent: "x")

        editMenu.addItem(withTitle: "Copy",
                         action: #selector(NSText.copy(_:)),
                         keyEquivalent: "c")

        editMenu.addItem(withTitle: "Paste",
                         action: #selector(NSText.paste(_:)),
                         keyEquivalent: "v")

        editMenu.addItem(withTitle: "Select All",
                         action: #selector(NSText.selectAll(_:)),
                         keyEquivalent: "a")

        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }
}

// --- Launch -----------------------------------------------------------------
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
