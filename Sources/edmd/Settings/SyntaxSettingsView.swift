import SwiftUI
import AppKit
import UniformTypeIdentifiers
import EdmundCore

/// The "Syntax" pane: a master switch for non-GFM syntax with the individual
/// extension toggles in a 2-column grid beneath it. The master is centered over
/// the grid; clearing it disables (and grays) every toggle at once. GFM callout
/// alerts (NOTE/TIP/…) and ordinary image dimensions have no toggle — the former
/// is always on (core GFM), the latter rides the master switch directly.
struct SyntaxSettingsView: View {
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
    @AppStorage(AppSettings.Key.defaultCodeSyntax)  private var defaultCodeSyntax = "plain"

    /// The selected row in the "Available syntax" list (a language id).
    @State private var selectedSyntax: String?
    /// Bumped after an import/removal so the popup + list re-read the store.
    @State private var defsVersion = 0

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, verticalSpacing: 18) {
            GridRow {
                Text("Markdown syntax:").gridColumnAlignment(.trailing)
                Toggle("Enable extended Markdown syntax", isOn: $enableNonGFM)
                    .onChange(of: enableNonGFM) { applyFeatures() }
                // TODO: add note here "Edmund is fully compatible with [GFM](https://github.github.com/gfm/) and provides optional support for [Obsidian-flavored Markdown](https://obsidian.md/help/obsidian-flavored-markdown)."
            }
            GridRow {
                Color.clear.frame(width: 0, height: 0)   // empty leading cell
                // The feature grid sits below the master switch and indented
                // further in, so the toggles read as its children.
                featureGrid
                    .padding(.leading, 20)
                    .disabled(!enableNonGFM)
            }

            GridRow { Divider().gridCellColumns(2) }

            // Code-block highlighting: the default language for untagged fences,
            // and the list of installed language definitions (bundled + user).
            GridRow {
                Text("Default code syntax:").gridColumnAlignment(.trailing)
                Picker("", selection: $defaultCodeSyntax) {
                    ForEach(languages, id: \.id) { Text($0.label).tag($0.id) }
                }
                .labelsHidden()
                .frame(width: boxWidth)   // match the list box below
                .onChange(of: defaultCodeSyntax) {
                    AppSettings.applyCodeSyntax()
                    refreshCodeBlocks()
                }
            }
            GridRow(alignment: .top) {
                Text("Available syntax:").gridColumnAlignment(.trailing)
                availableSyntaxList
            }
        }
        .settingsPanePadding()
    }

    /// The installed languages, "Plain Text" first. `defsVersion` is read so an
    /// import/removal re-evaluates this list.
    private var languages: [(id: String, label: String)] {
        _ = defsVersion
        return SyntaxDefinitionStore.shared.availableLanguages()
    }

    /// Fixed width shared by the list box and the "Default code syntax" popup,
    /// matching CotEditor's 260-pt syntax box.
    private let boxWidth: CGFloat = 260
    /// One list row's height; the box shows exactly 5 (`rowHeight * 5`).
    private let rowHeight: CGFloat = 24

    /// The CotEditor-style list of definitions with a `+ − ✎` toolbar. A single
    /// square `.border` wraps the (separator-less) list and the white toolbar bar
    /// — replicating FormatSettingsView's box. SwiftUI `List` covers the "menu";
    /// only the file actions touch AppKit.
    private var availableSyntaxList: some View {
        let defs = languages.filter { $0.id != "plain" }
        let selectionIsUser = selectedSyntax.map {
            SyntaxDefinitionStore.shared.isUserDefinition($0)
        } ?? false
        return VStack(spacing: 0) {
            List(selection: $selectedSyntax) {
                ForEach(defs, id: \.id) { lang in
                    Text(lang.label).tag(lang.id)
                        .listRowSeparator(.hidden)
                        // Indent every row from the box's left edge.
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 0))
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, rowHeight)
            .contentMargins(.vertical, 0, for: .scrollContent)  // no padding → exactly 5 rows
            .frame(height: rowHeight * 5)

            // A hairline lighter than the box border, inset so it doesn't touch
            // the box's left/right edges (CotEditor's toolbar separator).
            Rectangle()
                .fill(Color(white: 0.898))   // #e5e5e5
                .frame(height: 1)
                .padding(.horizontal, 6)
            HStack(spacing: 10) {
                Button(action: importDefinition) { Image(systemName: "plus") }
                    .help("Import a language definition (.json)")
                Button(action: removeDefinition) { Image(systemName: "minus") }
                    .help("Remove the selected user definition")
                    .disabled(!selectionIsUser)
                Button(action: revealDefinition) { Image(systemName: "pencil") }
                    .help("Show the definition's JSON file in the Finder")
                    // Built-ins live read-only inside the app bundle — only a
                    // user's own def has an editable file to reveal.
                    .disabled(!selectionIsUser)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(width: boxWidth)
        .border(Color(nsColor: .separatorColor))
    }

    private var featureGrid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24, verticalSpacing: 6) {
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
                cell("Obsidian callout > [!note]", $obsidianCallout)
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

    /// Re-styles every open document's code blocks (Edit + Read) after the
    /// default language or the installed definitions changed.
    private func refreshCodeBlocks() {
        for case let document as Document in NSDocumentController.shared.documents {
            document.editor?.rerenderStyles()
            document.refreshReadView()
        }
    }

    /// Reload the store from disk, refresh the UI, and re-highlight open docs.
    private func reloadDefinitions() {
        AppSettings.applyCodeSyntax()
        defsVersion += 1
        refreshCodeBlocks()
    }

    /// `+` — copy a chosen `.json` into ~/.edmund/syntaxes (overwriting a
    /// same-named file), then reload.
    private func importDefinition() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let src = panel.url else { return }

        let dir = SyntaxDefinitionStore.userDirectory
        let dest = dir.appendingPathComponent(src.lastPathComponent.lowercased())
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: src, to: dest)
        } catch {
            NSSound.beep()
            return
        }
        reloadDefinitions()
    }

    /// `−` — delete the selected user definition (built-ins have no file to remove).
    private func removeDefinition() {
        guard let id = selectedSyntax,
              SyntaxDefinitionStore.shared.isUserDefinition(id),
              let url = SyntaxDefinitionStore.shared.fileURL(forName: id) else { return }
        try? FileManager.default.removeItem(at: url)
        selectedSyntax = nil
        reloadDefinitions()
    }

    /// `✎` — reveal the selected user definition's JSON in the Finder. Enabled
    /// only for user defs (built-ins are read-only inside the app bundle).
    private func revealDefinition() {
        guard let id = selectedSyntax,
              SyntaxDefinitionStore.shared.isUserDefinition(id),
              let url = SyntaxDefinitionStore.shared.fileURL(forName: id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
