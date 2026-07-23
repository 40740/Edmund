// The Edit settings pane: how the editing view looks (Display) and how it
// behaves as you type (Editing).
//
// Several controls here are deliberately `.disabled(true)`: their setting is
// stored and the UI is final, but the feature behind them isn't built yet
// (invisible characters, indent guides, line numbers, focus mode, indent
// detection, strict line breaks, hard wrap). Each becomes live by deleting its
// `.disabled(true)` when the feature lands — see misc/backlog.md.

import SwiftUI
import AppKit
import EdmundCore

struct EditSettingsView: View {
    /// Inner-tab content inset. The pane's own breathing room comes from
    /// `settingsPanePadding()`; this is the gap inside the tab box.
    private let insets = EdgeInsets(top: 4, leading: 10, bottom: 10, trailing: 10)

    var body: some View {
        // A fixed height, sized to the taller tab: NSTabViewController resizes
        // the Settings window to each pane's preferred size, so a pane that
        // changed height when its *inner* tab changed would resize the window
        // out from under the click.
        TabView {
            DisplayEditsView()
                .padding(insets)
                .tabItem { Text("Display") }
            EditingEditsView()
                .padding(insets)
                .tabItem { Text("Editing") }
        }
        .frame(height: 380)
        .settingsPanePadding()
    }
}

// MARK: - Display

private struct DisplayEditsView: View {
    @AppStorage(AppSettings.Key.showToolbar)     private var showToolbar = true
    @AppStorage(AppSettings.Key.autoHideToolbar) private var autoHideToolbar = true
    @AppStorage(AppSettings.Key.sourceMode)      private var sourceMode = false
    @AppStorage(AppSettings.Key.showInvisibles) private var showInvisibles = false
    @AppStorage(AppSettings.Key.invisiblesMode)
    private var invisiblesMode = AppSettings.InvisibleCharacterMode.uponSelection
    @AppStorage(AppSettings.Key.invisibleLineEnding) private var lineEnding = true
    @AppStorage(AppSettings.Key.invisibleTab)        private var tab = true
    @AppStorage(AppSettings.Key.invisibleSpace)      private var space = true
    @AppStorage(AppSettings.Key.invisibleWhitespace) private var otherWhitespace = true
    @AppStorage(AppSettings.Key.invisibleControl)    private var otherControl = true
    @AppStorage(AppSettings.Key.showListIndentGuides) private var showListIndentGuides = false
    @AppStorage(AppSettings.Key.showLineNumbers)      private var showLineNumbers = false
    @AppStorage(AppSettings.Key.highlightCurrentLine) private var highlightCurrentLine = false

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, verticalSpacing: 18) {
            GridRow {
                // Cancel the extra space .leadingFirstTextBaseline adds above
                // the first row (both cells, so they stay aligned).
                Text("Toolbar:")
                    .gridColumnAlignment(.trailing)
                    .padding(.top, -6)
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Show toolbar", isOn: $showToolbar)
                    Toggle("Automatically hide toolbar in full screen", isOn: $autoHideToolbar)
                        .padding(.leading, 20)
                }
                .padding(.top, -6)
                .onChange(of: showToolbar) { AppSettings.applyEditSettingsToOpenDocuments() }
            }

            GridRow {
                Text("Editor:").gridColumnAlignment(.trailing)
                // The same setting as View ▸ Show Source in Editor.
                Toggle("Show raw source in editor", isOn: $sourceMode)
                    .onChange(of: sourceMode) { applySourceMode() }
            }

            // TODO: Move Max Content Width here, after Settings ▸ Themes

            GridRow {
                Text("Show:").gridColumnAlignment(.trailing)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        // fixedSize, or the picker's flexible width squeezes the
                        // label down to "Invisible charac…".
                        Toggle("Invisible characters", isOn: $showInvisibles)
                            .fixedSize()
                        // When to draw them, once they're on at all.
                        Picker("", selection: $invisiblesMode) {
                            ForEach(AppSettings.InvisibleCharacterMode.allCases) {
                                Text($0.label).tag($0)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .disabled(!showInvisibles)
                    }
                    invisibleCharacterGrid
                        .padding(.leading, 20)
                        .disabled(!showInvisibles)
                    
                    Toggle("List indent guides", isOn: $showListIndentGuides)
                        .disabled(true)   // not implemented yet
                    
                    // Leftmost of the window only — not in print / PDF, for now.
                    Toggle("Line numbers", isOn: $showLineNumbers)
                        .disabled(true)   // not implemented yet
                }
                .disabled(true)   // not implemented yet
            }

            GridRow {
                Text("Current line:").gridColumnAlignment(.trailing)
                Toggle("Focus mode", isOn: $highlightCurrentLine)
                    .disabled(true)   // not implemented yet
            }
        }
    }

    private var invisibleCharacterGrid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24, verticalSpacing: 6) {
            GridRow {
                cell("Line ending", $lineEnding)
                cell("Tab", $tab)
                cell("Space", $space)
            }
            GridRow {
                cell("Other whitespace", $otherWhitespace)
                cell("Other control characters", $otherControl)
                    .gridCellColumns(2)
            }
        }
    }

    /// One grid toggle, sized to its own text — without `fixedSize` the grid
    /// hands each column an equal share and the longer labels wrap.
    private func cell(_ label: String, _ binding: Binding<Bool>) -> some View {
        Toggle(label, isOn: binding)
            .fixedSize()
            .gridColumnAlignment(.leading)
    }

    /// The setting is already written by @AppStorage; each open document just
    /// needs to swap its editing view over.
    private func applySourceMode() {
        for case let document as Document in NSDocumentController.shared.documents {
            document.applySourceMode()
        }
    }
}

// MARK: - Editing

private struct EditingEditsView: View {
    @AppStorage(AppSettings.Key.indentStyle)
    private var indentStyle = AppSettings.IndentStyle.spaces
    @AppStorage(AppSettings.Key.indentWidth)       private var indentWidth = 2
    @AppStorage(AppSettings.Key.detectIndent)      private var detectIndent = true
    @AppStorage(AppSettings.Key.strictLineBreaks)  private var strictLineBreaks = true
    @AppStorage(AppSettings.Key.hardWrapLongLines) private var hardWrapLongLines = false
    @AppStorage(AppSettings.Key.autoCloseBrackets) private var autoCloseBrackets = true
    @AppStorage(AppSettings.Key.continueLists)     private var continueLists = true
    @AppStorage(AppSettings.Key.spellCheck)        private var spellCheck = false

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, verticalSpacing: 18) {
            GridRow {
                Text("Indentation:")
                    .gridColumnAlignment(.trailing)
                    .padding(.top, -6)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Prefer using")
                        Picker("", selection: $indentStyle) {
                            ForEach(AppSettings.IndentStyle.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    HStack(spacing: 6) {
                        Text("Indent width:")
                        TextField("", value: $indentWidth,
                                  format: .number.precision(.fractionLength(0)))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 24)
                        Stepper("", value: $indentWidth, in: 1...8)
                            .labelsHidden()
                        Text("spaces")
                    }
                    Toggle("Detect and learn indent style on document opening", isOn: $detectIndent)
                        .disabled(true)   // not implemented yet
                }
                .padding(.top, -6)
                .onChange(of: indentStyle) { AppSettings.applyEditSettingsToOpenDocuments() }
                .onChange(of: indentWidth) { AppSettings.applyEditSettingsToOpenDocuments() }
            }

            GridRow {
                Text("Lines:").gridColumnAlignment(.trailing)
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Strict line breaks", isOn: $strictLineBreaks)
                    Text("Markdown specs ignore single line breaks in read view. Turn off to make single line breaks visible.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 380, alignment: .leading)
                        .padding(.leading, 20)
                    Toggle("Automatically hard-wrap long lines", isOn: $hardWrapLongLines)
                }
                .disabled(true)   // not implemented yet
            }

            GridRow {
                Text("Content:").gridColumnAlignment(.trailing)
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Automatically insert closing parentheses and quotes",
                           isOn: $autoCloseBrackets)
                    Toggle("Automatically continue lists", isOn: $continueLists)
                }
                .onChange(of: autoCloseBrackets) { AppSettings.applyEditSettingsToOpenDocuments() }
                .onChange(of: continueLists) { AppSettings.applyEditSettingsToOpenDocuments() }
            }

            GridRow { Divider().gridCellColumns(2) }

            GridRow {
                Text("Spelling:").gridColumnAlignment(.trailing)
                Toggle("Check spelling while typing", isOn: $spellCheck)
                    .onChange(of: spellCheck) { AppSettings.applyEditSettingsToOpenDocuments() }
            }
        }
    }
}
