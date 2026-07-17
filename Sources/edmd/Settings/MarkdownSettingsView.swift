import SwiftUI
import AppKit

/// Toggles for each individually-switchable Markdown extension. Clearing one
/// makes that syntax render as plain text everywhere (Edit and Read), live.
struct MarkdownSettingsView: View {
    @AppStorage(AppSettings.Key.mdCallout)            private var callout = true
    @AppStorage(AppSettings.Key.mdCollapsibleCallout) private var collapsibleCallout = true
    @AppStorage(AppSettings.Key.mdWikilink)           private var wikilink = true
    @AppStorage(AppSettings.Key.mdWikilinkEmbed)      private var wikilinkEmbed = true
    @AppStorage(AppSettings.Key.mdHighlight)          private var highlight = true
    @AppStorage(AppSettings.Key.mdInlineComment)      private var inlineComment = true
    @AppStorage(AppSettings.Key.mdFootnote)           private var footnote = true
    @AppStorage(AppSettings.Key.mdMath)               private var math = true
    @AppStorage(AppSettings.Key.mdImageDimensions)    private var imageDimensions = true

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, verticalSpacing: 18) {
            GridRow {
                Text("Callouts:").gridColumnAlignment(.trailing)
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Callouts", isOn: $callout)
                        .onChange(of: callout) { applyFeatures() }
                    Toggle("Collapsible callouts ([!note]-/+)", isOn: $collapsibleCallout)
                        .onChange(of: collapsibleCallout) { applyFeatures() }
                        .disabled(!callout)
                        .padding(.leading, 20)
                }
            }

            GridRow { Divider().gridCellColumns(2) }

            GridRow {
                Text("Links & images:").gridColumnAlignment(.trailing)
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Wikilinks ([[note]])", isOn: $wikilink)
                        .onChange(of: wikilink) { applyFeatures() }
                    Toggle("Wikilink image embeds (![[image.png]])", isOn: $wikilinkEmbed)
                        .onChange(of: wikilinkEmbed) { applyFeatures() }
                        .padding(.leading, 20)
                    Toggle("Image dimensions (![alt|200](url))", isOn: $imageDimensions)
                        .onChange(of: imageDimensions) { applyFeatures() }
                }
            }

            GridRow { Divider().gridCellColumns(2) }

            GridRow {
                Text("Text:").gridColumnAlignment(.trailing)
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Highlights (==text==)", isOn: $highlight)
                        .onChange(of: highlight) { applyFeatures() }
                    Toggle("Inline comments (%%comment%%)", isOn: $inlineComment)
                        .onChange(of: inlineComment) { applyFeatures() }
                    Toggle("Footnotes ([^1])", isOn: $footnote)
                        .onChange(of: footnote) { applyFeatures() }
                    Toggle("Math ($…$, $$…$$)", isOn: $math)
                        .onChange(of: math) { applyFeatures() }
                }
            }
        }
        .settingsPanePadding()
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
