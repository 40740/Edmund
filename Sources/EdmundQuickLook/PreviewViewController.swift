import Cocoa
import QuickLookUI
import EdmundCore

// MARK: - Quick Look preview for Markdown
//
// Hosts the same `ReadModeWebView` the app uses for Read mode, so a Space-bar
// preview in Finder renders the document exactly as the editor does — links
// inert, math and local images inlined. The web view derives light/dark from its
// `effectiveAppearance` and re-renders on an appearance flip, so the preview
// follows the app's appearance setting with no extra code here.
//
// The `@objc` name is what `NSExtensionPrincipalClass` in the appex Info.plist
// references; Swift's mangled name would not resolve.
//
// ---
//
// "The preview still just spins, forever" (issue #8, third round).
//
// The previous revision tried to leave the eternal-spinner state by bounding the
// *wait*: `preparePreviewOfFile` awaited the web view's first `didFinish` with an
// 8-second deadline, and only then showed the document — or a stated reason. That
// still made the entire preview depend on a WebKit callback arriving on schedule,
// inside a host process we don't own, for a view that has never been attached to
// anything. When the callback didn't arrive, the deadline turned a
// forever-spinner into a spinner-plus-8s; and anything that stalled the main
// actor (a synchronous full recompose, a slow asset pass, an appex started
// without the activation it needs) stopped the extension from reaching even
// that, leaving Quick Look's own loading state on screen indefinitely.
//
// So the contract is inverted here:
//
//   `preparePreviewOfFile` neither renders nor waits. Its *return value* is the
//   finished preview — a view that is already complete on screen. Every outcome
//   is a view the user can read: the document, or a stated reason.
//
// The web view is created and asked to render while this method runs, but it is
// hidden the whole time and only swapped in later, by its own load callback —
// which is why a slow or stuck WebKit handoff can no longer hold the preview
// open. "Still loading" is not reachable from this code path, because nothing on
// it waits for anything.
//
// The one thing the swap-in can't fix on its own is *how long the render takes*,
// because `DocumentHTML.full` is synchronous work on the main actor. It is the
// same call Read mode makes on the same document, so it is not slow in practice
// — and when it is, the preview shows the document's HTML late rather than
// nothing at all, because the container it lands in is already on screen.

@objc(EdmundPreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController {

    /// The log line and the on-screen explanation for each way a preview can
    /// land. Kept together so a reason can never be logged without being
    /// showable (or vice versa).
    private enum Settled {
        case empty
        case unreadable
        case loadFailed

        var notice: String? {
            switch self {
            case .empty:      return "这个 Markdown 文件是空的"
            case .unreadable: return "无法读取这个文件（编码不受支持）"
            case .loadFailed: return "预览渲染失败，未能显示该文档（详见 ~/.edmund/logs）"
            }
        }
    }

    /// SwiftUI-hosted previews (`.quickLookPreview` / QLPreviewPanel) ask for a
    /// view controller, not a view; Finder asks for a file. Both end up here.
    override func loadView() {
        Log.info("loadView", category: .render)
        let root = PreviewContainer()
        // The preview follows System Settings ▸ Appearance. An appex can be
        // handed its view before the host has pushed its appearance down the
        // view tree, in which case `effectiveAppearance` still reads the
        // process default — so resolve it from the app's own setting here, and
        // let the view's ordinary `viewDidChangeEffectiveAppearance`
        // re-render take over afterwards.
        root.appearance = NSAppearance(named: Self.preferredAppearance())
        view = root
    }

    /// The appearance to render in, resolved exactly the way the app resolves it
    /// (`AppSettings.applyAppearance`): a ColaMD preset carries its own light/dark
    /// palette and wins over the appearance-mode picker; otherwise
    /// `settings.appearance.mode` decides, with anything unrecognised following
    /// the system. Both keys are read straight from UserDefaults because
    /// `AppSettings` lives in the app target and isn't linked here;
    /// `ColaThemePreset` is in `EdmundCore`, so the preset half is the same type
    /// the app uses.
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

    // MARK: - Entry point

    func preparePreviewOfFile(at url: URL) async throws {
        Log.info("preparePreviewOfFile: \(url.lastPathComponent)", category: .render)

        guard let markdown = Self.read(url) else {
            // A file we can't decode is not a render failure: say so and return.
            Log.error("could not read \(url.path) as text", category: .io)
            view = Self.noticeView(Settled.unreadable.notice ?? "")
            return
        }

        // Nothing below this line waits: `documentView` returns a finished
        // container (the web view inside it is still hidden), which is what makes
        // "still loading" unreachable as a preview outcome. The one input that
        // can't produce a document is checked here, before anything is built.
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Log.info("document is empty — showing the notice", category: .render)
            view = Self.noticeView(Settled.empty.notice ?? "")
            return
        }
        view = documentView(markdown: markdown, url: url)
    }

    // MARK: - Rendering

    /// Builds the view for `markdown`: a container that is a complete preview on
    /// its own (background, layout, appearance) with the rendered document inside,
    /// hidden until it reports its first load.
    ///
    /// Returning the container rather than the web view is the whole point — the
    /// caller can hand it to Quick Look immediately, whatever WebKit is doing.
    private func documentView(markdown: String, url: URL) -> NSView {
        // Does this preview get to inline the document's images? images are read
        // off disk, and the appex is sandboxed with access to the previewed file
        // only — so anything next to it is unreadable here, while the
        // (unsandboxed) app shows it fine. Ask for the plain-text fallback in
        // that case: the author's alt text reads as a document, a column of
        // "Image not found" icons doesn't. Probed, not hoped for.
        let imageAccess = Self.canReadDocumentDirectory(for: url)
        var options = ReadRenderOptions()
        // var + assignment, not the memberwise init: adding a parameter to
        // `ReadRenderOptions.init` would be a source-breaking change for every
        // caller (an extension's ABI is its own).
        options.plainTextImageFallback = !imageAccess
        Log.info("image access next to the document: \(imageAccess ? "granted" : "denied")",
                 category: .io)

        let container = PreviewContainer()
        let webView = ReadModeWebView()
        // Frame-based layout, not Auto Layout: an `NSView` with no intrinsic
        // content size and no constraints is zero-sized, so a constraint-driven
        // web view here would be laid out 0×0 and render nothing. The container
        // is the one thing Quick Look sizes, and autoresizing passes that size
        // straight down.
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        webView.isHidden = true          // shown by `reveal`, once it has painted
        container.addSubview(webView)

        // The load callback is the *only* thing that puts the document on
        // screen, and it runs after `preparePreviewOfFile` has already returned.
        // Container + "recently active" is what tells a late callback apart from
        // one belonging to a preview the user has already navigated away from.
        //
        // Retained by the container (below), not by the closure: a reveal held
        // only weakly by its own callback would be deallocated on the way out of
        // this method and never fire, which is indistinguishable from the bug
        // being fixed.
        let reveal = Reveal(container: container, webView: webView)
        container.reveal = reveal
        webView.onLoadFinished = { [weak reveal] in
            // The callback arrives on main already (the navigation coordinator is
            // main-actor isolated); hopping through `Task { @MainActor }` is what
            // keeps that assumption true if it ever isn't, without capturing the
            // web view strongly from inside its own callback.
            Task { @MainActor in
                reveal?.revealIfPreferred()
            }
        }

        webView.render(markdown: markdown,
                       theme: .quickLook,
                       callouts: Callout.defaultStyles,
                       baseURL: url.deletingLastPathComponent(),
                       options: options)

        return container
    }

    // MARK: - Reading

    /// Reads the file as text, preferring UTF-8 and falling back to Latin-1 the
    /// way the app does.
    private static func read(_ url: URL) -> String? {
        (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .isoLatin1))
    }

    // MARK: - Revealing the document

    /// Owns one preview's reveal: swaps the hidden web view in once it has
    /// loaded, but only if this is still the preview the user is looking at.
    ///
    /// Finder asks for a preview per selection change, and a previous document's
    /// load can land after the next one has been requested. Each reveal takes a
    /// place in that sequence when it is created; only the newest one is allowed
    /// to touch the screen. A superseded reveal is dropped — its container is no
    /// longer anyone's view, so there is nothing to show and nothing to clean up.
    @MainActor
    private final class Reveal {
        private let container: NSView
        private let webView: ReadModeWebView

        /// Bumped by every new reveal (main-actor only, like every caller).
        private static var generation = 0
        /// This reveal's place in that sequence.
        private let mine: Int

        init(container: NSView, webView: ReadModeWebView) {
            self.container = container
            self.webView = webView
            Self.generation += 1
            self.mine = Self.generation
        }

        func revealIfPreferred() {
            guard mine == Self.generation else {
                Log.info("dropping reveal for a superseded preview", category: .render)
                return
            }
            guard !webView.lastLoadFailed else {
                // WebKit said the page couldn't be shown. Replace the (never
                // revealed) document with the reason, so the preview isn't an
                // empty pane.
                Log.error("preview load failed — showing the notice instead", category: .render)
                container.subviews.forEach { $0.removeFromSuperview() }
                let notice = PreviewViewController.noticeView(Settled.loadFailed.notice ?? "")
                notice.frame = container.bounds
                notice.autoresizingMask = [.width, .height]
                container.addSubview(notice)
                return
            }
            // Match the web view to the size the container was given, then show
            // it. Quick Look sizes the root view after `preparePreviewOfFile`
            // returns, so the bounds are only known here.
            webView.frame = container.bounds
            webView.isHidden = false
            Log.info("preview revealed", category: .render)
        }
    }

    // MARK: - Views

    /// The preview's root view: whatever size Quick Look gives it, passed
    /// straight down to the one subview (see `documentView`).
    ///
    /// Deliberately *not* flipped. A flipped container would place the frame-based
    /// web view by top-left origin while WebKit — and every other AppKit view
    /// here — expects Cocoa's bottom-left, so the web view would sit at the wrong
    /// end of the pane for the frames before the reveal. Matching the default
    /// coordinate space keeps the two consistent.
    ///
    /// Holds the reveal, because the reveal is what the web view's load callback
    /// needs to reach — and that callback must not be the thing keeping it alive
    /// (see `documentView`). The view outlives the callback by construction: it is
    /// the preview Quick Look is showing.
    private final class PreviewContainer: NSView {
        var reveal: Reveal?
    }

    /// A centered message, filling itself into whatever container it is given.
    private static func noticeView(_ text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 15)
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = PreviewContainer()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
        ])
        return container
    }

    /// Whether this process may read files in the document's directory — the
    /// precondition for inlining the images a markdown document references.
    /// A *successful* `contentsOfDirectory` is the evidence: it needs the same
    /// access a subsequent file read would. (No `startAccessingSecurityScoped…`
    /// here: the sandbox grants the previewed file, and probing is cheaper than
    /// tracking scoped access for a directory we only read from.)
    private static func canReadDocumentDirectory(for url: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)) != nil
    }
}
