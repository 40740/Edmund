// The Edit settings pane: one page, in three sections separated by rules —
// the window chrome, what typing does, and what you see.

import SwiftUI
import AppKit
import EdmundCore

struct EditSettingsView: View {
    @AppStorage(AppSettings.Key.showToolbar)     private var showToolbar = true
    @AppStorage(AppSettings.Key.autoHideToolbar) private var autoHideToolbar = true
    @AppStorage(AppSettings.Key.sourceMode)      private var sourceMode = false
    @AppStorage(AppSettings.Key.showInvisibles) private var showInvisibles = false
    // Parked with the rest of the Always mode — see the "Characters:" row.
    // @AppStorage(AppSettings.Key.invisiblesMode)
    // private var invisiblesMode = AppSettings.InvisibleCharacterMode.uponSelection
    @AppStorage(AppSettings.Key.invisibleLineEnding) private var lineEnding = true
    @AppStorage(AppSettings.Key.invisibleTab)        private var tab = true
    @AppStorage(AppSettings.Key.invisibleSpace)      private var space = true
    @AppStorage(AppSettings.Key.invisibleWhitespace) private var otherWhitespace = true
    @AppStorage(AppSettings.Key.invisibleControl)    private var otherControl = true
    @AppStorage(AppSettings.Key.showListIndentGuides) private var showListIndentGuides = false
    @AppStorage(AppSettings.Key.showLineNumbers)      private var showLineNumbers = false
    @AppStorage(AppSettings.Key.lineNumbersByWindowEdge)
    private var lineNumbersByWindowEdge = false
    @AppStorage(AppSettings.Key.typewriterMode) private var typewriterScroll = true
    @AppStorage(AppSettings.Key.focusMode) private var focusMode = false
    @AppStorage(AppSettings.Key.indentStyle)
    private var indentStyle = AppSettings.IndentStyle.spaces
    @AppStorage(AppSettings.Key.indentWidth)       private var indentWidth = 2
    @AppStorage(AppSettings.Key.detectIndent)      private var detectIndent = true
    @AppStorage(AppSettings.Key.strictLineBreaks)  private var strictLineBreaks = true
    @AppStorage(AppSettings.Key.hardWrapLongLines) private var hardWrapLongLines = false
    @AppStorage(AppSettings.Key.detectMaxLineLength) private var detectMaxLineLength = true
    @AppStorage(AppSettings.Key.autoCloseBrackets) private var autoCloseBrackets = true
    @AppStorage(AppSettings.Key.continueLists)     private var continueLists = true
    @AppStorage(AppSettings.Key.spellCheck)        private var spellCheck = false 

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, verticalSpacing: 18) {
            // MARK: - Window-level settings
            GridRow {
                // Cancel the extra space .leadingFirstTextBaseline adds above
                // the first row (both cells, so they stay aligned).
                Text("Toolbar:")
                    .gridColumnAlignment(.trailing)
                    .padding(.top, -6)
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Show toolbar", isOn: $showToolbar)
                    Toggle("Automatically hide toolbar in full screen", isOn: autoHideInFullScreen)
                        .padding(.leading, 20)
                        .disabled(!showToolbar)
                }
                .padding(.top, 2)
                .onChange(of: showToolbar) { AppSettings.applyEditSettingsToOpenDocuments() }
            }
            
            // TODO: Move Max Content Width here, after Settings ▸ Themes 
            
            GridRow {
                Text("Editor:").gridColumnAlignment(.trailing)
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Typewriter scroll", isOn: $typewriterScroll)
                        .onChange(of: typewriterScroll) { AppSettings.applyEditSettingsToOpenDocuments() }
                    Toggle("Focus mode", isOn: $focusMode)
                        .onChange(of: focusMode) { AppSettings.applyEditSettingsToOpenDocuments() }
                    Text("Dim all but current line and selection.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 380, alignment: .leading)
                        .padding(.leading, 20)
                }
            }
            
            GridRow {
                Text("Source mode:").gridColumnAlignment(.trailing)
                // The same setting as View ▸ Show Source in Editor
                Toggle("Show raw source in editor", isOn: $sourceMode)
                    .onChange(of: sourceMode) { applySourceMode() }
            }
            
            GridRow { Divider().gridCellColumns(2) }

            // MARK: - Content-level editing settings
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
                }
                .padding(.top, -6)
                .onChange(of: indentStyle) { AppSettings.applyEditSettingsToOpenDocuments() }
                .onChange(of: indentWidth) { AppSettings.applyEditSettingsToOpenDocuments() }
            }
            
            GridRow {
                Text("Words:")
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Automatically insert closing parentheses and quotes", isOn: $autoCloseBrackets)
                    Toggle("Check spelling while typing", isOn: $spellCheck)
                }
                .onChange(of: autoCloseBrackets) { AppSettings.applyEditSettingsToOpenDocuments() }
                .onChange(of: spellCheck) { AppSettings.applyEditSettingsToOpenDocuments() }
            }
            
            GridRow {
                Text("Lists:")
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Show list indent guides", isOn: $showListIndentGuides)
                        .onChange(of: showListIndentGuides) { AppSettings.applyEditSettingsToOpenDocuments() }
                    Toggle("Automatically continue lists", isOn: $continueLists)
                        .onChange(of: continueLists) { AppSettings.applyEditSettingsToOpenDocuments() }
                }
            }
            
            GridRow { Divider().gridCellColumns(2) }
                        
            // MARK: - Content-level display settings
            GridRow {
                Text("Characters:").gridColumnAlignment(.trailing)
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Show invisible characters upon selection", isOn: $showInvisibles)
                    // The mode picker this toggle replaced (commit 6652972),
                    // parked in case Always comes back. Restoring it also needs
                    // AppSettings.InvisibleCharacterMode, its key/accessor, and
                    // InvisiblesConfig.Mode — all commented at their sites.
                    //
                    // HStack {
                    //     // fixedSize, or the picker's flexible width squeezes the
                    //     // label down to "Invisible charac…".
                    //     Toggle("Show invisible characters", isOn: $showInvisibles)
                    //         .fixedSize()
                    //     // When to draw them, once they're on at all.
                    //     Picker("", selection: $invisiblesMode) {
                    //         ForEach(AppSettings.InvisibleCharacterMode.allCases) {
                    //             Text($0.label).tag($0)
                    //         }
                    //     }
                    //     .labelsHidden()
                    //     .fixedSize()
                    //     .disabled(!showInvisibles)
                    // }
                    invisibleCharacterGrid
                        .padding(.leading, 20)
                        .padding(.bottom, -15)  // hardcoded
                        .disabled(!showInvisibles)
                }
                .onChange(of: showInvisibles) { AppSettings.applyEditSettingsToOpenDocuments() }
                // .onChange(of: invisiblesMode) { AppSettings.applyEditSettingsToOpenDocuments() }
                .onChange(of: lineEnding) { AppSettings.applyEditSettingsToOpenDocuments() }
                .onChange(of: tab) { AppSettings.applyEditSettingsToOpenDocuments() }
                .onChange(of: space) { AppSettings.applyEditSettingsToOpenDocuments() }
                .onChange(of: otherWhitespace) { AppSettings.applyEditSettingsToOpenDocuments() }
                .onChange(of: otherControl) { AppSettings.applyEditSettingsToOpenDocuments() }
            }
            
            GridRow {
                Text("Lines:").gridColumnAlignment(.trailing)
                VStack(alignment: .leading, spacing: 6) {
                    // Not in print / PDF, for now.
                    Toggle("Show line numbers", isOn: $showLineNumbers)
                        .onChange(of: showLineNumbers) { AppSettings.applyEditSettingsToOpenDocuments() }
                    // Off: the numbers sit in the reading column's own margin.
                    // On: they move out to a gutter at the window's leading edge,
                    // which reserves width and so re-centers the column.
                    Toggle("Show line numbers by window edge", isOn: $lineNumbersByWindowEdge)
                        .padding(.leading, 20)
                        .disabled(!showLineNumbers)
                        .onChange(of: lineNumbersByWindowEdge) { AppSettings.applyEditSettingsToOpenDocuments() }

                    Toggle("Strict line breaks", isOn: $strictLineBreaks)
                        .onChange(of: strictLineBreaks) { refreshReadViews() }
                    Text("Markdown specs ignore single line breaks in read view. Turn off to make single line breaks visible.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 380, alignment: .leading)
                        .padding(.leading, 20)
                }
            }
            
            GridRow {
                Text("Document:").gridColumnAlignment(.trailing)
                VStack(alignment: .leading, spacing: 6) {
                    // Joining lines only makes sense while a single newline is
                    // formatting rather than content — see the note below the
                    // strict line breaks toggle.
                    Toggle("Automatically hard-wrap long lines", isOn: $hardWrapLongLines)
                        .disabled(!strictLineBreaks)
                    // Off → every wrapped file is re-wrapped at 80, which
                    // reflows one written at any other width on its first save.
                    Toggle("Detect max line length on document opening",
                           isOn: $detectMaxLineLength)
                        .padding(.leading, 20)
                        .disabled(!strictLineBreaks || !hardWrapLongLines)
                    Text("Files that are already hard-wrapped are joined into single lines "
                         + "for editing and re-wrapped on save, at the width they already "
                         + "use or 80 characters. Other files are left alone — use "
                         + "Edit ▸ Hard Wrap Paragraphs.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 380, alignment: .leading)
                        .padding(.leading, 20)
                }
            }
        }
        .settingsPanePadding()
    }

    /// With the toolbar hidden outright there is nothing left to auto-hide, so
    /// the checkbox reads as on and greys out. It reports `true` rather than
    /// writing it, so whatever the user actually picked comes back untouched
    /// when the toolbar returns.
    private var autoHideInFullScreen: Binding<Bool> {
        Binding(get: { showToolbar ? autoHideToolbar : true },
                set: { autoHideToolbar = $0 })
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

    /// Strict line breaks changes Read-mode output, so re-render every open
    /// document (Read mode reads `AppSettings.strictLineBreaks` on render).
    private func refreshReadViews() {
        for case let document as Document in NSDocumentController.shared.documents {
            document.refreshReadView()
        }
    }
}
