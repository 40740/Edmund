import AppKit
import QuickLookUI
import EdmundRender
import EdmundMarkdown

// MARK: - Quick Look preview for Markdown
//
// Renders the document with the same `DocumentHTML` pipeline the app's Read mode
// uses — links inert, math and local images inlined — and hands Quick Look a view
// that is *already complete* by the time `preparePreviewOfFile` returns, because
// Quick Look keeps its loading state on screen until it does.
//
// The `@objc` name is what `NSExtensionPrincipalClass` in the appex Info.plist
// references; Swift's mangled name would not resolve.
//
// ---
//
// "扩展 com.i7t5.edmund.quicklook 在预览此文稿期间失败" (issue #8, fourth round).
//
// That is not the forever-spinner of the previous three rounds — it is Quick
// Look saying the extension **failed** (no usable view, or an appex that never
// became a preview extension). Four things were wrong, all of them in what the
// extension *is* rather than in what it renders:
//
// 1. **The appex linked the entire editor.** The extension target depended on
//    all of `EdmundCore` — the TextKit 2 editor, the extension host, the syntax
//    highlighter, the RaTeX/WASM math host, SwiftMath's fonts — none of which a
//    preview touches. A preview extension is started on the Space-bar path, and
//    every one of those is imported and initialized in the appex process before
//    the first preview can be drawn. The target now depends on two small modules
//    (`EdmundRender` → `EdmundMarkdown`) that carry only parsing + HTML, and the
//    preview links neither AppKit's editor stack nor WebKit's JS machinery
//    brought in by the editor.
// 2. **The view was never laid out.** The previous revision returned a container
//    and sized a *hidden* web view inside it by `autoresizingMask`, on the
//    theory that the container would be resized and push the new size down.
//    Autoresizing only fires when the superview's *own* frame changes through
//    `setFrameSize`; a view handed to a host that installs Auto Layout
//    constraints on it never does. Measured: the container stayed 0×0, so the
//    web view was 0×0, so the preview had nothing of any size to show.
//    `viewWillAppear` + `viewDidLayout` now place the web view at the size the
//    host actually gave, with a floor so a zero-sized hand-off still renders
//    something.
// 3. **The appex had no bundle, no Info.plist and no appearance.** Built as a
//    bare executable and wrapped by `cp`, it ran as a windowless process with
//    no `CFBundle` at all, and `NSApp.effectiveAppearance` there is the
//    *unbundled* process default — so dark mode could not be resolved at all.
//    The build now emits a real appex (`Info.plist`, extension marker, signed
//    with its entitlements) and the preview resolves its own appearance from the
//    app's setting instead of inheriting one from a window it never gets.
// 4. **The extension ran the app's document machinery.** `NSDocumentController`
//    opened the previewed file through `Document` — an 800×520 window, toolbar,
//    sidebar and all — inside the appex. The extension no longer links the app
//    target at all, so none of that machinery exists to be started.
//
// Nothing here is "waiting" for anything: every path through
// `preparePreviewOfFile` returns an answer, and the answer is drawn synchronously
// from HTML that is already in memory.

@objc(EdmundPreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController {

    /// The on-screen explanation for each way a preview can land. Kept together
    /// so a reason can never be logged without being showable (or vice versa).
    ///
    /// All three are reachable *after* `preparePreviewOfFile` has returned: the
    /// page is handed to WebKit and the view goes up immediately, so a load that
    /// fails (`.renderFailed`) is stated in the pane by `showLoadFailure` once its
    /// callback lands, rather than holding the preview open for it.
    private enum Settled {
        case empty
        case unreadable
        case renderFailed

        var notice: String {
            switch self {
            case .empty:        return "这个 Markdown 文件是空的"
            case .unreadable:   return "无法读取这个文件（编码不受支持）"
            case .renderFailed: return "预览渲染失败，未能显示该文档（详见 ~/.edmund/logs）"
            }
        }
    }

    /// The view handed to the host. It draws the page background itself and tracks
    /// where the host put it, which is what the web view is laid out against (see
    /// `viewDidLayout`). It also owns the appearance: an appex has no window whose
    /// appearance it could inherit (Quick Look owns the panel), so a change has to
    /// be observed here, on the view, rather than on the controller.
    private final class PreviewContainer: NSView {
        var onLayout: (() -> Void)?
        var onAppearanceChange: (() -> Void)?

        override func layout() {
            super.layout()
            onLayout?()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            onAppearanceChange?()
        }
    }

    private let container = PreviewContainer()
    /// Created once, on the first document, and reused: a WKWebView is the most
    /// expensive object in this process, and Quick Look keeps the controller
    /// alive as the user pages through a folder.
    private var webView: ReadModeWebView?
    /// The document currently previewed and the appearance it was rendered in,
    /// so an appearance change can rebuild the page.
    private var currentDocument: (markdown: String, url: URL)?
    private var currentDocumentIsDark = false

    override func loadView() {
        Log.info("loadView", category: .render)
        container.appearance = NSAppearance(named: Self.preferredAppearance())
        container.onLayout = { [weak self] in self?.layoutWebView() }
        container.onAppearanceChange = { [weak self] in self?.appearanceChanged() }
        view = container
    }

    // MARK: - Appearance
    //
    // An appex is not "the app": in a process with no preference domain of its
    // own, `UserDefaults.standard` is empty, so the app's appearance preference
    // has to be read from the *shared* domain — which is what a user default
    // written by the app is visible through in every process that runs as the
    // same user, sandboxed or not.
    //
    // The extension has no window to inherit an appearance from either (Quick
    // Look owns the panel), so `effectiveAppearance` here is just the process
    // default. Resolving it from the app's rule instead — a ColaMD preset wins
    // over the light/dark picker, otherwise the picker, otherwise the system —
    // is what stops dark mode rendering a white page.

    private static func preferredAppearance() -> NSAppearance.Name {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "settings.appearance.themePreset"),
           let preset = ColaThemePreset(rawValue: raw),
           let forcedDark = preset.forcedDark {
            return forcedDark ? .darkAqua : .aqua
        }
        switch defaults.string(forKey: "settings.appearance.mode") {
        case "light": return .aqua
        case "dark":  return .darkAqua
        default:      return NSApp.effectiveAppearance.name
        }
    }

    private var isDark: Bool {
        container.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    // MARK: - Entry point

    func preparePreviewOfFile(at url: URL) async throws {
        Log.info("preparePreviewOfFile: \(url.lastPathComponent)", category: .render)

        guard let markdown = Self.read(url) else {
            // A file we can't decode is not a render failure: say so and return.
            Log.error("could not read \(url.path) as text", category: .io)
            show(Settled.unreadable)
            return
        }
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Log.info("document is empty — showing the notice", category: .render)
            show(Settled.empty)
            return
        }
        showDocument(markdown: markdown, url: url)
    }

    // MARK: - Rendering
    //
    // The whole render happens here, synchronously, because everything it needs
    // is already in memory: `DocumentHTML.full` turns the markdown into one
    // self-contained HTML string (math rasterized, local images inlined as data
    // URIs, theme CSS included) and the web view paints it without fetching
    // anything. Nothing on this path waits for a callback, which is exactly why
    // "still loading" is not a reachable outcome.

    private func showDocument(markdown: String, url: URL) {
        currentDocument = (markdown, url)
        currentDocumentIsDark = isDark
        let webView = self.webView ?? ReadModeWebView()
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = [.width, .height]
        if webView.superview !== container {
            container.subviews.forEach { $0.removeFromSuperview() }
            container.addSubview(webView)
            self.webView = webView
        }
        layoutWebView()
        // The load is asynchronous — the view is already on screen when it lands —
        // so a failure is reported *here* rather than by replacing the view in
        // `preparePreviewOfFile`. Without this the pane would just stay empty.
        webView.onLoadFinished = { [weak self, weak webView] in
            guard let self, let webView, webView === self.webView else { return }
            reportRenderDiagnostics(webView)
            if webView.lastLoadFailed { showLoadFailure() }
        }
        webView.render(html: Self.html(for: markdown, url: url, dark: currentDocumentIsDark),
                       theme: .quickLook, dark: currentDocumentIsDark)
    }

    /// The page WebKit was handed could not be shown. Stated in the pane, so the
    /// preview is never an unexplained empty rectangle — the shape issue #8 kept
    /// taking, where "nothing" was indistinguishable from "still working".
    private func showLoadFailure() {
        let why = webView?.lastLoadFailureReason.map { ": \($0)" } ?? ""
        Log.error("preview load failed\(why)", category: .render)
        show(.renderFailed)
    }

    /// Writes the render pipeline's *recorded* diagnostics to the log.
    ///
    /// `EdmundRender` sits below the module that owns the logger, so
    /// `DocumentHTML` collects what it had to substitute rather than logging it.
    /// The extension reports them here — a preview that shows less than the
    /// document is otherwise a mystery, and the log is the one artefact a user can
    /// send back. The web view's load is asynchronous, so its own failure lands in
    /// the log from `webViewDidFail`, below.
    private func reportRenderDiagnostics(_ webView: ReadModeWebView) {
        for reason in RenderOutcome.lastRunReasons {
            Log.error(reason.message, category: .render)
        }
    }


    /// The complete page for one document in one appearance. Assembled once per
    /// render — by `showDocument` for the first one, and again by
    /// `viewDidChangeEffectiveAppearance` when the appearance changes.
    private static func html(for markdown: String, url: URL, dark: Bool) -> String {
        DocumentHTML.full(
            markdown: markdown,
            theme: .quickLook,
            callouts: Callout.defaultStyles,
            dark: dark,
            baseURL: url.deletingLastPathComponent(),
            options: readOptions()
        )
    }

    // MARK: - The app's render settings
    //
    // The preview has no `AppSettings` (it doesn't link the app target — see the
    // header), so the handful of preferences that change what a *preview* shows
    // are read here, by the same keys `AppSettings.Key` declares. When left at
    // their defaults these resolve to the app's defaults, which is what a fresh
    // install previews with.

    /// The app's Read-mode render options (`AppSettings.readRenderOptions`).
    private static func readOptions() -> ReadRenderOptions {
        var options = ReadRenderOptions()
        options.preserveBlankLines = bool("settings.reading.renderBlankLinesAsBreaks", default: true)
        options.allowRemoteImages = !bool("settings.advanced.blockExternalImages", default: false)
        options.maxContentWidthPoints = maxContentWidthPoints()
        options.features = MarkdownFeatures.all
        return options
    }

    /// The centered reading column, in points. The app derives this from the
    /// `settings.appearance.maxContentWidthCm` preference and the display's
    /// physical PPI; without a display to measure here the app's own default
    /// (12 cm / 5 in — `AppSettings.defaultMaxContentWidthCm`) is converted at
    /// the 109 PPI figure `AppSettings` falls back to when the display can't be
    /// measured. A preview panel is normally narrower than the column anyway.
    private static func maxContentWidthPoints() -> Double {
        let cm = UserDefaults.standard.object(forKey: "settings.appearance.maxContentWidthCm") as? Double
            ?? (Locale.current.measurementSystem == .us ? 5.0 * 2.54 : 12.0)
        return cm / 2.54 * 109
    }

    private static func bool(_ key: String, default fallback: Bool) -> Bool {
        (UserDefaults.standard.object(forKey: key) as? Bool) ?? fallback
    }

    // MARK: - Layout
    //
    // The one thing a preview must get right is having a size. Quick Look gives
    // its view controller a frame (or constraints) of its own choosing, and
    // nothing else here may depend on that being non-zero — an `NSView` with no
    // intrinsic size is 0×0, and a 0×0 web view renders nothing at all.
    //
    // The container is laid out by the host, so `layout()` (called for both
    // frame-based and constraint-based hosts) is where the web view is given the
    // size the host actually chose. The floor only applies when the host
    // genuinely hasn't given us one.

    override func viewWillAppear() {
        super.viewWillAppear()
        layoutWebView()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutWebView()
    }

    // MARK: - Appearance changes

    /// The appearance this preview renders in changed. The page is
    /// appearance-specific — background, ink and code colours are baked into its
    /// CSS — so it has to be rebuilt, and only this layer knows the markdown it
    /// was built from (the web view was handed a finished string).
    private func appearanceChanged() {
        guard let document = currentDocument, let webView, isDark != currentDocumentIsDark else {
            return
        }
        currentDocumentIsDark = isDark
        webView.render(html: Self.html(for: document.markdown, url: document.url,
                                       dark: currentDocumentIsDark),
                       theme: .quickLook, dark: currentDocumentIsDark)
    }

    /// The web view's size for the container's current bounds. `container.bounds`
    /// is whatever the host actually gave us; the floor (see `minimumSize`) only
    /// applies when it gave us nothing.
    private func layoutWebView() {
        guard let webView else { return }
        let bounds = container.bounds
        let size = NSSize(width: max(bounds.width, Self.minimumSize.width),
                          height: max(bounds.height, Self.minimumSize.height))
        guard webView.frame.size != size else { return }
        webView.frame = NSRect(origin: .zero, size: size)
        Log.info("web view laid out at \(Int(size.width))×\(Int(size.height))", category: .render)
    }

    /// What a preview is given when the host hasn't said how big it is yet.
    private static let minimumSize = NSSize(width: 480, height: 320)

    // MARK: - Reading the file

    /// Reads the file as text, preferring UTF-8 and falling back to Latin-1 the
    /// way the app does.
    private static func read(_ url: URL) -> String? {
        (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .isoLatin1))
    }

    // MARK: - Views

    /// Replaces whatever is on screen with a stated reason. Every one of these
    /// is a finished preview in its own right.
    private func show(_ settled: Settled) {
        webView?.removeFromSuperview()
        webView = nil
        currentDocument = nil
        container.subviews.forEach { $0.removeFromSuperview() }

        let label = NSTextField(wrappingLabelWithString: settled.notice)
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 15)
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
        ])
    }
}
