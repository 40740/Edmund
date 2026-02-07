import AppKit

// --- App Delegate -----------------------------------------------------------

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Markdown Editor"
        window.center()

        // Build the text system chain properly:
        //   NSTextStorage → NSLayoutManager → NSTextContainer → NSTextView
        // This ensures hit-testing, cursor placement, and selection all work.
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let contentSize = NSSize(width: 720, height: CGFloat.greatestFiniteMagnitude)
        let textContainer = NSTextContainer(size: contentSize)
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        // Create EditorTextView with the properly configured text container.
        let editor = EditorTextView(
            frame: NSRect(x: 0, y: 0, width: 720, height: 640),
            textContainer: textContainer
        )
        editor.minSize = NSSize(width: 0, height: 0)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainerInset = NSSize(width: 48, height: 32)

        // Scroll view
        let scrollView = NSScrollView(frame: window.contentView!.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = editor

        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// --- Launch -----------------------------------------------------------------
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
