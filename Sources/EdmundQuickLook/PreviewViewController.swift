import Cocoa
import QuickLookUI
import EdmundCore

// MARK: - Quick Look preview for Markdown
//
// Hosts the same `ReadModeWebView` the app uses for Read mode, so a Space-bar
// preview in Finder renders the document exactly as the editor does — links
// inert, math and local images inlined. The web view derives light/dark from its
// `effectiveAppearance` and re-renders on a system appearance flip, so the
// preview follows System Settings ▸ Appearance with no extra code here.
//
// The `@objc` name is what `NSExtensionPrincipalClass` in the appex Info.plist
// references; Swift's mangled name would not resolve.
//
// On "the preview just spins forever" (issue #8, second round): Quick Look shows
// its loading state until `preparePreviewOfFile` *returns*. This used to await
// the web view's `didFinish` with no way out — so anything that stopped that
// callback (a web-content process that never came up, a render that threw) left
// the preview loading for good, with no explanation and nothing in a log. Three
// things close that hole:
//   1. `waitForLoad` has a deadline; a render that doesn't finish in time is
//      reported as a failure the user can see, not an endless spinner.
//   2. Renders that *do* finish are still checked — an empty document, a page
//      that came out blank, or a page whose images had to be replaced are all
//      surfaced in the preview itself (and logged).
//   3. Every step is logged to `~/.edmund/logs/` (see main.swift), so a bad
//      preview leaves behind the reason it was bad.
@objc(EdmundPreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController {

    private let webView = ReadModeWebView()

    /// How long a render may take before the preview gives up and reports it.
    /// Generous: a large document with math/images is CPU work, and the cost of
    /// being wrong here is a nice document being called timed-out. The cost of
    /// having *no* bound is the bug this exists to fix — an eternal spinner.
    private static let renderDeadline: TimeInterval = 8

    override func loadView() {
        Log.info("loadView", category: .render)
        view = webView
    }

    func preparePreviewOfFile(at url: URL) async throws {
        Log.info("preparePreviewOfFile: \(url.lastPathComponent)", category: .render)
        let markdown = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .isoLatin1))
        guard let markdown else {
            // Let Quick Look show its own "can't preview" state rather than
            // pinning a spinner: a file we can't decode is not a render failure.
            Log.error("could not read \(url.path) as text", category: .io)
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        Log.info("read \(markdown.count) chars; rendering", category: .render)

        // Can this preview show the document's images? Images are inlined by
        // reading them off disk, and a preview extension is sandboxed with access
        // to the previewed file only — so anything next to it is expected to be
        // unreadable here, while the (unsandboxed) app shows it fine. Ask for the
        // plain-text fallback in that case: the author's alt text in the image's
        // place reads as a document; a column of "Image not found" icons doesn't.
        // Probed once, on the document's own directory, rather than hoped for.
        let imageAccess = canReadDocumentDirectory(for: url)
        var options = ReadRenderOptions()
        // var + assignment, not the memberwise init: adding a parameter to
        // `ReadRenderOptions.init` would be a source-breaking change for every
        // caller (an extension's ABI is its own), and the default here must stay
        // the app's, so only this one field is overridden.
        options.plainTextImageFallback = !imageAccess
        options.plainTextImageFallback = !imageAccess
        Log.info("image access next to the document: \(imageAccess ? "granted" : "denied")",
                 category: .io)

        webView.render(markdown: markdown,
                       theme: .quickLook,
                       callouts: Callout.defaultStyles,
                       baseURL: url.deletingLastPathComponent(),
                       options: options)

        let outcome = await waitForRender()
        switch outcome {
        case .finished:
            let degraded = DocumentHTML.lastRenderUsedFallbacks
            let loadFailed = webView.lastLoadFailed
            Log.info("render finished (degraded: \(degraded), loadFailed: \(loadFailed))",
                     category: .render)
            if loadFailed {
                showNotice("预览渲染失败，未能显示该文档（详见 ~/.edmund/logs）")
            } else if markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                showNotice("这个 Markdown 文件是空的")
            } else if degraded {
                showNotice(imageAccess
                    ? "部分内容无法在此预览中渲染（详见 ~/.edmund/logs）"
                    : "图片无法在访达预览中显示（预览扩展受沙盒限制）")
            }
        case .timedOut:
            Log.error("render timed out after \(Self.renderDeadline)s — showing the notice",
                      category: .render)
            showNotice("预览渲染超时，未能显示该文档（详见 ~/.edmund/logs）")
        }
    }

    // MARK: - Waiting for the render

    private enum RenderOutcome { case finished, timedOut }

    /// Resolves when the web view reports its first load finished, or when the
    /// deadline passes. Exactly one of the two — a late `didFinish` after a
    /// timeout is ignored, so a slow page can't turn into an unexpected second
    /// resume. `preparePreviewOfFile` returning is what tells Quick Look the
    /// preview is ready, so this must always return.
    @MainActor
    private func waitForRender() async -> RenderOutcome {
        await withCheckedContinuation { (cont: CheckedContinuation<RenderOutcome, Never>) in
            var finished = false
            // `deadline` re-enters the main actor before touching the shared
            // state, and the render callback is delivered on main — so the flag
            // needs no lock.
            let deadline = Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.renderDeadline))
                guard !finished else { return }
                finished = true
                cont.resume(returning: .timedOut)
            }
            webView.onLoadFinished = { [weak self] in
                self?.webView.onLoadFinished = nil
                guard !finished else { return }
                finished = true
                deadline.cancel()
                cont.resume(returning: .finished)
            }
        }
    }

    // MARK: - Fallbacks the user can actually see

    /// Replaces the (possibly blank) web view with a plain message. Used when the
    /// preview cannot show the document: better a stated reason in the preview
    /// pane than a document that is silently absent or half-rendered.
    private func showNotice(_ text: String) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 15)
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
        ])
        webView.onLoadFinished = nil
        view = container
    }

    /// Whether this process may read files in the document's directory — the
    /// precondition for inlining the images a markdown document references.
    /// A *successful* `contentsOfDirectory` is the evidence: it needs the same
    /// access a subsequent file read would. (No `startAccessingSecurityScoped…`
    /// here: the sandbox grants the previewed file, and probing is cheaper than
    /// tracking scoped access for a directory we only read from.)
    private func canReadDocumentDirectory(for url: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)) != nil
    }
}
