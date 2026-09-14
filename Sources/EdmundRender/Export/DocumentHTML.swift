import AppKit
import EdmundMarkdown

// MARK: - DocumentHTML
//
// Assembles the full, self-contained HTML document for Read mode and PDF export:
// the `HTMLRenderer` body, the `HTMLTheme` stylesheet, and a second pass that
// fills the renderer's placeholder elements with inlined assets (math
// glyphs and local images) as data URIs. Callout/checkbox icons are inline
// Lucide SVGs emitted by `HTMLRenderer` (no asset pass needed). Inlining keeps
// the document self-contained — the webview needs no file/network access.
// Raw HTML in the markdown passes through per GFM, filtered by
// `HTMLRenderer.filterRawHTML` (tagfilter + hardening); the page also carries a
// `script-src 'none'` CSP meta as defense-in-depth (§G, ARCHITECTURE §10).

/// What the last render produced: whether the page just built is the document, or
/// the document with visibly substituted fallbacks (a failed rasterization, an
/// image this process can't read). `DocumentHTML`'s own bookkeeping is private,
/// so this is the public name for it.
public enum RenderOutcome {
    /// True when the most recent `DocumentHTML.full(...)` render replaced
    /// something it couldn't produce — a failed math rasterization, an image this
    /// process isn't allowed to read — with a visible stand-in. The preview uses
    /// it to say so on screen rather than presenting a silently incomplete page.
    @MainActor public static var lastRunUsedFallbacks: Bool {
        DocumentHTML.lastRenderUsedFallbacks
    }

    /// Everything the most recent render had to substitute, with the why. The
    /// caller reports these (see `DocumentHTML.lastPassReasons`).
    @MainActor public static var lastRunReasons: [DocumentHTML.RenderReason] {
        DocumentHTML.lastPassReasons
    }
}

@MainActor
public enum DocumentHTML {

    /// Set by the most recent `full(...)` call when an asset it could not render
    /// was replaced by a visible fallback (a failed rasterization, or an image
    /// this process isn't allowed to read). Callers that show the page to a user
    /// — the Quick Look preview — surface it on screen, instead of presenting a
    /// page that silently isn't the document.
    @MainActor public private(set) static var lastPassDegraded = false

    /// Everything the last render had to substitute, in the order it happened.
    /// Populated alongside `lastPassDegraded`, with the *why*: a render that
    /// degrades silently is what makes "the preview shows the wrong thing"
    /// unfalsifiable. The caller reports them, so they land in the log with the
    /// context of whatever was being rendered.
    @MainActor public private(set) static var lastPassReasons: [RenderReason] = []

    /// One substituted asset, and why.
    public enum RenderReason: Equatable, Sendable {
        /// The math engine produced nothing for this equation.
        case mathFailed(latex: String)
        /// The engine produced an image that couldn't be turned into a PNG.
        case mathRasterFailed(latex: String)
        /// An image was replaced by its alt text / a placeholder.
        case imageSubstituted(source: String, reason: String)
        /// This process isn't allowed to read the directory the images are in.
        case imageDirectoryUnreadable(path: String)

        /// A one-line description, in the shape the log wants.
        public var message: String {
            switch self {
            case .mathFailed(let latex):        return "math engine produced nothing for \(latex)"
            case .mathRasterFailed(let latex):  return "math raster failed for \(latex)"
            case .imageSubstituted(let source, let why): return "image substituted (\(why)): \(source)"
            case .imageDirectoryUnreadable(let path):
                return "not allowed to read images in \(path); degraded to placeholders"
            }
        }
    }

    /// Read-only view of `lastPassDegraded` for the `RenderOutcome` shim above.
    @MainActor static var lastRenderUsedFallbacks: Bool { lastPassDegraded }

    /// Builds a complete `<!DOCTYPE html>…` document for `markdown`. `baseURL` is
    /// the document's directory, used to resolve relative image paths for inlining.
    public static func full(markdown: String,
                     theme: EditorTheme,
                     callouts: [String: CalloutStyle],
                     dark: Bool,
                     baseURL: URL? = nil,
                     options: ReadRenderOptions = .default) -> String {
        lastPassDegraded = false
        lastPassReasons = []
        var body = HTMLRenderer.render(markdown: markdown, options: options)
        body = fillMath(body, theme: theme, dark: dark)
        body = fillImages(body, baseURL: baseURL, options: options,
                          plainTextFallback: options.plainTextImageFallback)
        let css = HTMLTheme.css(theme, callouts: callouts, dark: dark,
                                maxContentWidthPoints: options.maxContentWidthPoints)
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="script-src 'none'">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(css)
        </style></head>
        <body><div class="page">\(body)</div></body></html>
        """
    }

    // MARK: Math (active engine → PNG data URI)

    private static let inlineMathPattern = "<span class=\"math-inline\" data-tex=\"([^\"]*)\"></span>"
    // Group 1 is the block's `edmund-l<N>` source-line anchor (see
    // `HTMLRenderer.addingAnchorID`), when the display-math div is a top-level
    // block — carried through into the replacement so the anchor survives the
    // asset-fill pass.
    private static let displayMathPattern = "<div( id=\"[^\"]*\")? class=\"math-display\" data-tex=\"([^\"]*)\"></div>"
    // A `$$…$$` embedded in a prose line: display-mode rendering, but flowed
    // inline like `$…$` (matches the editor). Distinct class from the block div.
    private static let displayInlineMathPattern = "<span class=\"math-display-inline\" data-tex=\"([^\"]*)\"></span>"

    private static func fillMath(_ html: String, theme: EditorTheme, dark: Bool) -> String {
        // Same ink as the editor draws its equations in — one definition for both
        // modes (EditorTheme.bodyTextColor). Resolved against `dark` rather than
        // the current appearance because an export can target either.
        let color = EditorTheme.bodyTextColorResolved(dark: dark)
        var out = replaceMatches(html, pattern: displayMathPattern) { groups in
            let id = groups[1]
            let tex = unescapeAttr(groups[2])
            guard let (image, _) = mathPNG(latex: tex, displayMode: true,
                                           pointSize: theme.fontSize, color: color) else {
                return "<div\(id) class=\"math-display\"><code>\(HTMLRenderer.escape(tex))</code></div>"
            }
            let uri = "data:image/png;base64,\(image.data.base64EncodedString())"
            return "<div\(id) class=\"math-display\"><img class=\"math\" style=\"width:\(fmt(image.cssWidth))px; height:\(fmt(image.cssHeight))px\" src=\"\(uri)\" alt=\"\(HTMLRenderer.attr(tex))\"></div>"
        }
        out = replaceMatches(out, pattern: inlineMathPattern) { groups in
            let tex = unescapeAttr(groups[1])
            guard let (image, descent) = mathPNG(latex: tex, displayMode: false,
                                                 pointSize: theme.fontSize,
                                                 color: color) else {
                return "<code>\(HTMLRenderer.escape(tex))</code>"
            }
            let uri = "data:image/png;base64,\(image.data.base64EncodedString())"
            // Explicit width AND height, derived from the PNG's own pixel
            // dimensions (not independently rounded from the NSImage's point
            // size) — guarantees an exact native-pixel-to-CSS-pixel ratio, so
            // the browser scales the bitmap by precisely 2x with no resampling.
            // A width/height that's merely "close" to 2x (e.g. 91 native px
            // shown at a declared 45px — ratio 2.02, not 2.0) still forces a
            // slight resample, which measurably thinned 1-2px strokes like the
            // "=" sign's bars (confirmed via connected-component pixel
            // measurement, not guessed). `vertical-align` is a position, not a
            // size, so rounding it to a whole pixel (separately) still avoids
            // the sub-pixel compositing blur that caused — same reasoning,
            // different axis.
            return "<img class=\"math math-inline\" style=\"width:\(fmt(image.cssWidth))px; height:\(fmt(image.cssHeight))px; vertical-align:\(fmt(-descent.rounded()))px\" src=\"\(uri)\" alt=\"\(HTMLRenderer.attr(tex))\">"
        }
        out = replaceMatches(out, pattern: displayInlineMathPattern) { groups in
            let tex = unescapeAttr(groups[1])
            // Display math embedded in a prose line still gets its own centered
            // block (a `<span>` promoted to display:block, since the placeholder
            // sits inside a `<p>` where a `<div>` would be invalid). The
            // paragraph's text keeps flowing above and below it.
            guard let (image, _) = mathPNG(latex: tex, displayMode: true,
                                           pointSize: theme.fontSize, color: color) else {
                return "<span class=\"math-display-block\"><code>\(HTMLRenderer.escape(tex))</code></span>"
            }
            let uri = "data:image/png;base64,\(image.data.base64EncodedString())"
            return "<span class=\"math-display-block\"><img class=\"math\" style=\"width:\(fmt(image.cssWidth))px; height:\(fmt(image.cssHeight))px\" src=\"\(uri)\" alt=\"\(HTMLRenderer.attr(tex))\"></span>"
        }
        return out
    }

    /// Renders math and returns its bitmap, or nil when the engine produced
    /// nothing *or* the raster pass failed. Callers fall back to the raw TeX in a
    /// `<code>`, never to an empty hole — a page missing an equation with no sign
    /// anything is absent is a partial copy of the document, not a rendering of it.
    private static func mathPNG(latex: String, displayMode: Bool,
                                pointSize: CGFloat, color: NSColor) -> (image: ImageRaster.PNGResult, descent: CGFloat)? {
        // `renderingErrors: true` (the default): a document must render every
        // equation, so malformed LaTeX comes out as readable flattened text
        // rather than the raw `<code>` fallback below — a typo in a document
        // should still look like the equation it was meant to be, and the whole
        // page stays legible even when no typesetter is available.
        guard let rendered = MathRendering.shared.render(latex: latex, displayMode: displayMode,
                                                         pointSize: pointSize, color: color,
                                                         renderingErrors: true) else {
            // `RenderedMath` is the engine-agnostic result; rasterizing it is the
            // HTML pipeline's job, which is why the PNG step lives here and not
            // with the engine (the editor draws the same `NSImage` directly).
            lastPassReasons.append(.mathFailed(latex: String(latex.prefix(60))))
            lastPassDegraded = true
            return nil
        }
        guard let png = ImageRaster.pngData(rendered.image, scale: 2) else {
            // Recorded, not logged: the caller reports it (see `lastPassReasons`),
            // so the line lands in the log with the context of this render.
            lastPassReasons.append(.mathRasterFailed(latex: String(latex.prefix(60))))
            lastPassDegraded = true
            return nil
        }
        return (png, rendered.descent)
    }

    // MARK: Images (local → inlined data URI; remote → off by default)

    // Groups 3/4 are optional declared dimensions from an HTML `<img>` tag
    // (captured with their leading space so they re-emit verbatim).
    private static let imagePattern =
        "<img class=\"md-image\" data-src=\"([^\"]*)\" alt=\"([^\"]*)\"( width=\"[0-9]+\")?( height=\"[0-9]+\")?>"

    /// Resolves each `md-image` placeholder: local/relative paths are read and
    /// inlined as a data URI (self-contained, no file access needed at render
    /// time); a `data:` source passes through; remote `https` sources load only
    /// when `options.allowRemoteImages` is set. Anything that can't be shown
    /// gets a visible icon + reason (`ImageLoadFailure`, shared with Edit
    /// mode's inline preview) instead of silently showing nothing.
    private static func fillImages(_ html: String, baseURL: URL?,
                                   options: ReadRenderOptions,
                                   plainTextFallback: Bool = false) -> String {
        var cache: [String: String] = [:]   // resolved path → data URI
        /// So an unreadable image directory is reported once, not once per image.
        var warnedDirectories = Set<String>()

        /// The visible stand-in for an image this process couldn't read. The
        /// Quick Look preview runs inside a sandboxed appex whose only file
        /// access is the document being previewed, so a page with local images
        /// comes out all placeholder icons — the reason a preview can look empty
        /// while the app renders the same file fine. That context asks for the
        /// alt text instead: the author's own words in the image's place.
        func placeholder(_ src: String, alt: String, reason: ImageLoadFailure) -> String {
            lastPassDegraded = true
            lastPassReasons.append(.imageSubstituted(source: src, reason: reason.label))
            if plainTextFallback {
                let label = unescapeAttr(alt).trimmingCharacters(in: .whitespacesAndNewlines)
                return "<span class=\"md-image-omitted\">\(HTMLRenderer.escape(label.isEmpty ? src : label))</span>"
            }
            return blockedImagePlaceholder(reason: reason)
        }

        /// True when the file exists but this process may not read it (sandbox
        /// denial, permissions) — the case that needs explaining rather than
        /// being reported as "missing".
        func denied(_ fileURL: URL) -> Bool {
            guard !FileManager.default.isReadableFile(atPath: fileURL.path) else { return false }
            if warnedDirectories.insert(fileURL.deletingLastPathComponent().path).inserted {
                lastPassReasons.append(
                    .imageDirectoryUnreadable(path: fileURL.deletingLastPathComponent().path))
            }
            return true
        }

        return replaceMatches(html, pattern: imagePattern) { groups in
            let src = unescapeAttr(groups[1])
            let alt = groups[2]   // already attribute-escaped by the renderer
            let dims = groups[3] + groups[4]   // optional ` width="N" height="N"`

            if src.isEmpty { return placeholder(src, alt: alt, reason: .notFound) }
            let lower = src.lowercased()
            if lower.hasPrefix("data:") {
                return "<img class=\"md-image\" src=\"\(HTMLRenderer.attr(src))\" alt=\"\(alt)\"\(dims)>"
            }
            if lower.hasPrefix("http://") {
                return placeholder(src, alt: alt, reason: .httpUnsupported)
            }
            if lower.hasPrefix("https://") {
                guard options.allowRemoteImages else {
                    return placeholder(src, alt: alt, reason: .blockedBySetting)
                }
                return "<img class=\"md-image\" src=\"\(HTMLRenderer.attr(src))\" alt=\"\(alt)\"\(dims)>"
            }
            // Local: resolve against the document directory, read, inline.
            guard let fileURL = resolveLocalImage(src, baseURL: baseURL) else {
                return placeholder(src, alt: alt, reason: .notFound)
            }
            if let cached = cache[fileURL.path] {
                return "<img class=\"md-image\" src=\"\(cached)\" alt=\"\(alt)\"\(dims)>"
            }
            // `resolveLocalImage`'s absolute/`~` branches don't check existence
            // (only the relative-path branch does), so a missing file and an
            // undecodable one would otherwise fail `imageDataURI` identically —
            // check existence first so the two get distinct, accurate messages.
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return placeholder(src, alt: alt, reason: .notFound)
            }
            if denied(fileURL) { return placeholder(src, alt: alt, reason: .notReadable) }
            guard let uri = imageDataURI(fileURL) else {
                return placeholder(src, alt: alt, reason: .notAnImage)
            }
            cache[fileURL.path] = uri
            return "<img class=\"md-image\" src=\"\(uri)\" alt=\"\(alt)\"\(dims)>"
        }
    }

    /// A visible stand-in for an image that can't be shown: an icon plus a
    /// short reason, instead of just empty space.
    private static func blockedImagePlaceholder(reason: ImageLoadFailure) -> String {
        let icon = LucideIcons.inlineSVG("image-off") ?? ""
        return "<span class=\"md-image-blocked\">\(icon)<span>\(reason.label)</span></span>"
    }

    /// Resolves a local image `path` to a file URL: absolute / `~` / `file:`
    /// load directly; a relative path resolves against the document's directory.
    private static func resolveLocalImage(_ path: String, baseURL: URL?) -> URL? {
        if let url = URL(string: path), url.scheme == "file" { return url }
        // A markdown image destination may be percent-encoded (e.g. `%20`).
        let decoded = path.removingPercentEncoding ?? path
        if decoded.hasPrefix("/") { return URL(fileURLWithPath: decoded) }
        if decoded.hasPrefix("~") { return URL(fileURLWithPath: (decoded as NSString).expandingTildeInPath) }
        guard let baseURL else { return nil }
        let resolved = baseURL.appendingPathComponent(decoded)
        return FileManager.default.fileExists(atPath: resolved.path) ? resolved : nil
    }

    /// Reads an image file and returns a `data:` URI, with the MIME type guessed
    /// from the file extension (covers the common web image formats). Decodes
    /// the bytes first (discarding the result) so a file that merely has an
    /// image extension but isn't actually image data is caught here — as
    /// "Not an image" — rather than silently inlining garbage the browser
    /// then fails to render with no explanation.
    private static func imageDataURI(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), NSImage(data: data) != nil else { return nil }
        let mime: String
        switch url.pathExtension.lowercased() {
        case "png":          mime = "image/png"
        case "jpg", "jpeg":  mime = "image/jpeg"
        case "gif":          mime = "image/gif"
        case "svg":          mime = "image/svg+xml"
        case "webp":         mime = "image/webp"
        case "bmp":          mime = "image/bmp"
        case "tiff", "tif":  mime = "image/tiff"
        default:             mime = "application/octet-stream"
        }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    // MARK: Bitmap / escaping helpers

    /// A rasterized PNG plus the CSS `width`/`height` (`pixelSize / scale`)
    /// that exactly matches it — declaring anything else forces WebKit to
    /// resample the bitmap, which is what was thinning 1-2px strokes.


    /// Reverses the HTML-attribute escaping done by `HTMLRenderer.attr` so the
    /// raw LaTeX/symbol can be recovered from a placeholder attribute.
    private static func unescapeAttr(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<")
         .replacingOccurrences(of: "&gt;", with: ">")
         .replacingOccurrences(of: "&quot;", with: "\"")
         .replacingOccurrences(of: "&#39;", with: "'")
         .replacingOccurrences(of: "&amp;", with: "&")   // last, by convention
    }

    /// Finds every match of `pattern` and replaces it with `transform(groups)`,
    /// where `groups[0]` is the whole match. Replaces back-to-front so ranges
    /// stay valid.
    private static func replaceMatches(_ html: String, pattern: String,
                                       _ transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.dotMatchesLineSeparators]) else { return html }
        let ns = html as NSString
        let result = NSMutableString(string: html)
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        for m in matches.reversed() {
            var groups: [String] = []
            for i in 0..<m.numberOfRanges {
                let r = m.range(at: i)
                groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            result.replaceCharacters(in: m.range(at: 0), with: transform(groups))
        }
        return result as String
    }

    private static func fmt(_ v: CGFloat) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}
