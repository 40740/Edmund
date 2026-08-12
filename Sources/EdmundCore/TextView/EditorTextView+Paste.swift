import AppKit

// MARK: - Plain-text paste
//
// NSTextView's default `paste` reads the RICHEST format on the pasteboard and
// converts it to an attributed string. When text was copied from another app —
// a browser, Pages, a web page, a PDF — that conversion walks the pasteboard's
// HTML / RTF / RTFD (often many style runs) and can take many seconds for a
// sizable chunk. That is the "loading 十几秒 / 很卡" felt when pasting external
// text into Edmund.
//
// This editor is a Markdown editor: it recomposes and restyles everything
// itself on every edit (attribute-only, via `recomposeDirty`), so any rich
// attributes the default paste produced are thrown away the instant the edit is
// re-rendered. Converting the pasteboard's rich formats is pure wasted work.
//
// We therefore paste as PLAIN TEXT: read only the `.string` representation and
// insert it directly through the normal edit pipeline (shouldChangeText → undo
// record → didChangeText → incremental parse → restyle). Same result, no costly
// rich-text conversion, no paste lag. Fully offline — no impact on the open /
// save path.

extension EditorTextView {

    /// Paste as plain text. Falls back to the standard rich-text path only when
    /// the pasteboard has no plain-text representation (e.g. an image or a
    /// format that has no `.string` form), so the user is never stuck.
    public override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string) else {
            super.paste(sender)
            return
        }
        // Replace the current selection with the pasted text through the normal
        // editing pipeline. `super.insertText` (not the auto-pair override) so
        // pasting never auto-closes brackets, and the single bulk edit funnels
        // through didChangeText once.
        super.insertText(text, replacementRange: selectedRange())
    }
}
