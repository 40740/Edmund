import Foundation
import EdmundMarkdown

/// User-configurable options for the Read-mode / export HTML rendering. Kept in
/// EdmundCore (no AppKit/UserDefaults dependency) so the renderer stays pure;
/// the app layer reads the values from `AppSettings` and passes them in.
public struct ReadRenderOptions: Sendable, Equatable {

    /// When true, runs of blank lines in the source add proportional vertical
    /// space in the output (one extra blank line → one extra line of space),
    /// preserving the author's intentional spacing instead of collapsing it the
    /// way Markdown normally does.
    public var preserveBlankLines: Bool

    /// When true, remote (`http`/`https`) image URLs are loaded in the rendered
    /// document. Off by default so Read mode makes no surprise network requests;
    /// local images are always inlined regardless of this flag.
    public var allowRemoteImages: Bool

    /// The centered reading column's max width in points, matching the editor's
    /// `EditorTextView.maxContentWidthPoints` (§EditorTextView+ContentWidth). CSS
    /// px and AppKit points are both device-independent, so the same number caps
    /// the column to the same physical width in Read mode as in Edit mode.
    /// `.greatestFiniteMagnitude` → uncapped (fills the page).
    public var maxContentWidthPoints: Double

    /// Which Markdown extensions to recognize (highlight, callouts, wikilinks,
    /// math, …). Mirrors the editor's `EditorTextView.markdownFeatures` so Read
    /// mode and Edit mode agree on what's a feature vs. plain text. A cleared
    /// flag drops that syntax from the rendered HTML.
    public var features: MarkdownFeatures

    /// When true, an image the renderer can't show — most importantly one this
    /// process isn't allowed to read — is replaced by the author's alt text (or
    /// the source path) instead of a placeholder icon and a reason label.
    ///
    /// Set by the Quick Look preview. A preview runs in a sandboxed appex whose
    /// only file access is the previewed document, so images next to the file
    /// are, by construction, unreadable there — while the embedded editor (not
    /// sandboxed) shows them fine. Reporting "Image not found" would be plainly
    /// wrong, and a page of warning icons reads as "the preview is broken".
    /// Keeping the author's own words in place keeps the preview a usable
    /// reading of the document.
    public var plainTextImageFallback: Bool

    /// When true (the Markdown default), a single source newline is a *soft*
    /// break — collapsed to a space/newline so the two lines flow as one
    /// paragraph. When false, each single newline renders as a visible `<br>`,
    /// so the author's line breaks show up literally in Read mode.
    public var strictLineBreaks: Bool

    public init(preserveBlankLines: Bool = true, allowRemoteImages: Bool = false,
                maxContentWidthPoints: Double = .greatestFiniteMagnitude,
                features: MarkdownFeatures = .all, strictLineBreaks: Bool = true,
                plainTextImageFallback: Bool = false) {
        self.preserveBlankLines = preserveBlankLines
        self.allowRemoteImages = allowRemoteImages
        self.maxContentWidthPoints = maxContentWidthPoints
        self.features = features
        self.strictLineBreaks = strictLineBreaks
        self.plainTextImageFallback = plainTextImageFallback
    }

    public static let `default` = ReadRenderOptions()
}
