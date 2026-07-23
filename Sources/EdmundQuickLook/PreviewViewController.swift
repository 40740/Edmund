import Cocoa
import QuickLookUI
import EdmundCore
import os.log

private let qlLog = Logger(subsystem: "com.i7t5.edmund.quicklook", category: "preview")

// MARK: - Quick Look preview for Markdown
//
// Hosts the same `ReadModeWebView` the app uses for Read mode, so a Space-bar
// preview in Finder renders the document exactly as the editor does — math and
// local images inlined, links inert. The web view derives light/dark from its
// `effectiveAppearance` and re-renders on a system appearance flip, so the
// preview follows System Settings ▸ Appearance with no extra code here.
//
// The `@objc` name is what `NSExtensionPrincipalClass` in the appex Info.plist
// references; Swift's mangled name would not resolve.
@objc(EdmundPreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController {

    private let webView = ReadModeWebView()

    override func loadView() {
        qlLog.log("loadView")
        view = webView
    }

    func preparePreviewOfFile(at url: URL) async throws {
        qlLog.log("preparePreviewOfFile: \(url.lastPathComponent, privacy: .public)")
        let markdown = try String(contentsOf: url, encoding: .utf8)
        qlLog.log("read \(markdown.count) chars; rendering")
        // Await the first render so Quick Look snapshots the finished page rather
        // than a blank/loading web view — preparePreviewOfFile returning is the
        // signal that the preview is ready to display.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            webView.onLoadFinished = { [weak self] in
                self?.webView.onLoadFinished = nil
                cont.resume()
            }
            webView.render(markdown: markdown,
                           theme: .quickLook,
                           callouts: Callout.defaultStyles,
                           baseURL: url.deletingLastPathComponent(),
                           options: ReadRenderOptions())
        }
        qlLog.log("render finished")
    }
}
