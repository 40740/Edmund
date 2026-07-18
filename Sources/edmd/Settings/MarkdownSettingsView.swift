import SwiftUI
import AppKit

/// The "Syntax" pane: a master switch for non-GFM syntax with the individual
/// extension toggles in a 2-column grid beneath it. The master is centered over
/// the grid; clearing it disables (and grays) every toggle at once. GFM callout
/// alerts (NOTE/TIP/…) and ordinary image dimensions have no toggle — the former
/// is always on (core GFM), the latter rides the master switch directly.
struct MarkdownSettingsView: View {
    @AppStorage(AppSettings.Key.enableNonGFM)       private var enableNonGFM = true
    @AppStorage(AppSettings.Key.synFrontMatter)     private var frontMatter = true
    @AppStorage(AppSettings.Key.synMath)            private var math = true
    @AppStorage(AppSettings.Key.synHighlight)       private var highlight = true
    @AppStorage(AppSettings.Key.synComment)         private var comment = true
    @AppStorage(AppSettings.Key.synWikilink)        private var wikilink = true
    @AppStorage(AppSettings.Key.synTag)             private var tag = true
    @AppStorage(AppSettings.Key.synBlockRef)        private var blockRef = true
    @AppStorage(AppSettings.Key.synFootnote)        private var footnote = true
    @AppStorage(AppSettings.Key.synObsidianCallout) private var obsidianCallout = true

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, verticalSpacing: 18) {
            GridRow {
                Text("Master switch:").gridColumnAlignment(.trailing)
                Toggle("Enable non-GFM syntax", isOn: $enableNonGFM)
                    .onChange(of: enableNonGFM) { applyFeatures() }
            }
            GridRow {
                Color.clear.frame(width: 0, height: 0)   // empty leading cell
                // The feature grid sits below the master switch and indented
                // further in, so the toggles read as its children.
                featureGrid
                    .padding(.leading, 20)
                    .disabled(!enableNonGFM)
            }
        }
        .settingsPanePadding()
    }

    private var featureGrid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 28, verticalSpacing: 10) {
            GridRow {
                cell("Front matter (YAML)", $frontMatter)
                cell("Math ($ & $$)", $math)
            }
            GridRow {
                cell("==Highlight==", $highlight)
                cell("%%Comment%%", $comment)
            }
            GridRow {
                cell("[[Wikilink]]", $wikilink)
                cell("#tag", $tag)
            }
            GridRow {
                cell("Block ^1", $blockRef)
                cell("Footnote [^1]", $footnote)
            }
            GridRow {
                cell("Obsidian-flavored callout > [!note]", $obsidianCallout)
                    .gridCellColumns(2)
            }
        }
    }

    /// One grid toggle. Left-aligned within its column (Grid aligns the columns);
    /// intrinsic width so the whole grid stays compact and centers under the
    /// master switch. Broadcasts on change.
    private func cell(_ label: String, _ binding: Binding<Bool>) -> some View {
        Toggle(label, isOn: binding)
            .onChange(of: binding.wrappedValue) { applyFeatures() }
            .gridColumnAlignment(.leading)
    }

    /// Pushes the assembled feature set into every open document's editor and
    /// Read view so the change takes effect immediately.
    private func applyFeatures() {
        let features = AppSettings.markdownFeatures
        for case let document as Document in NSDocumentController.shared.documents {
            document.editor?.markdownFeatures = features
            document.refreshReadView()
        }
    }
}
