import AppKit

// MARK: - Services Provider (right-click ▸ Services)
//
// Backs the two `NSServices` entries declared in Info.plist. Registered as
// `NSApp.servicesProvider` in `applicationDidFinishLaunching`. The
// `AutoreleasingUnsafeMutablePointer<NSString?>` error parameter is the mandated
// shape of a Services selector — there is no other signature.
@MainActor
@objc final class ServicesProvider: NSObject {

    /// "Open in Edmund" — the pasteboard carries file URLs. Unlike an App
    /// Intent's `IntentFile`, a Services file URL is the real on-disk path (no
    /// sandbox copy), so this is the reliable "open the actual file" route.
    @objc func openInEdmund(_ pboard: NSPasteboard, userData: String,
                            error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        guard !urls.isEmpty else {
            error.pointee = "No files were provided." as NSString
            return
        }
        for url in urls {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// "New Edmund Document with Selection" — the pasteboard carries plain text.
    @objc func newDocumentWithSelection(_ pboard: NSPasteboard, userData: String,
                                        error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pboard.string(forType: .string) else {
            error.pointee = "No text was provided." as NSString
            return
        }
        (NSDocumentController.shared as? DocumentController)?.newDocument(withContent: text)
        NSApp.activate(ignoringOtherApps: true)
    }
}
