// The Extensions settings pane: a master-detail list of the app's optional
// extensions (today: "Advanced Math", the RaTeX engine option). Sidebar in
// the CotEditor/Safari style; detail pane modeled on Obsidian's plugin
// browser (misc/frontend-refs/obsidian-plugin-installed.png).

import SwiftUI
import AppKit
import EdmundCore

struct ExtensionsSettingsView: View {
    @State private var selectedID: String? = ExtensionRegistry.all.first?.id
    @State private var enabledIDs: Set<String> = AppSettings.enabledExtensionIDs
    @State private var installedExpanded = true
    @State private var recommendedExpanded = true
    private var selected: EdmundExtension? {
        ExtensionRegistry.all.first { $0.id == selectedID }
    }

    private var installed: [EdmundExtension] { ExtensionRegistry.all.filter(\.isInstalled) }
    private var recommended: [EdmundExtension] { ExtensionRegistry.all.filter { !$0.isInstalled } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Two separate boxes with the window background between and around
            // them, as in Safari's Extensions pane
            // (misc/frontend-refs/settings-safari-extensions.png), rather than
            // one panel filling the pane.
            HStack(spacing: 12) {
                sidebar
                detail
            }
            .frame(height: 300)

            HStack {
                Spacer()
                Button("More extensions…") {
                    // STUB: link to GitHub extensions repo for now.
                    // Extensions marketplace comes later.
                }
            }
        }
        .padding(20)
        // Every settings pane is 600 wide, so switching tabs only ever resizes
        // the window vertically.
        .frame(width: 600)
        .focusEffectDisabled()
    }

    private var sidebar: some View {
        List(selection: $selectedID) {
            sidebarSection("Installed", items: installed, isExpanded: $installedExpanded)
            sidebarSection("Recommended", items: recommended, isExpanded: $recommendedExpanded)
        }
        // `.plain`, not `.sidebar`, for the same reason the Key Bindings menu
        // list is plain: a sidebar list insets and rounds its selection into a
        // pill, while a plain list fills the whole row width — the selection bar
        // this pane wants. A List also paints its own background either way, so
        // the shared surface color only shows once that is hidden.
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .settingsSurfaceBackground()
        .frame(width: 170)
        .border(.separator)
    }

    private var detail: some View {
        Group {
            if let selected {
                ExtensionDetailView(
                    ext: selected,
                    isEnabled: Binding(
                        get: { enabledIDs.contains(selected.id) },
                        set: { setEnabled($0, for: selected.id) }
                    )
                )
                .id(selected.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text("No extensions installed.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .settingsSurfaceBackground()
        .border(.separator)
    }

    /// One collapsible sidebar group. Omitted entirely when empty — an
    /// "Installed" header with nothing under it reads as a broken list.
    ///
    /// Header and items are emitted as sibling rows rather than wrapped in a
    /// `Section`, and the header is hand-built rather than a `DisclosureGroup`.
    /// Both substitutions are forced by `.listStyle(.sidebar)`:
    ///
    /// - `DisclosureGroup` hangs its chevron to the *left* of the label and
    ///   indents its children under it. Finder puts the affordance after the
    ///   title and keeps rows at the sidebar's own margin.
    /// - A `Section` in a sidebar list becomes an outline group that owns its
    ///   own collapsed state. With a custom header that state can't be reached,
    ///   so it stayed collapsed while this view's `isExpanded` flipped
    ///   underneath it — the chevron animated and the rows never appeared.
    ///   Flat rows have no second disclosure state to disagree with.
    @ViewBuilder
    private func sidebarSection(_ title: String, items: [EdmundExtension],
                                isExpanded: Binding<Bool>) -> some View {
        if !items.isEmpty {
            Button {
                withAnimation(.snappy(duration: 0.18)) { isExpanded.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
            .listRowSeparator(.hidden)
            .selectionDisabled()

            if isExpanded.wrappedValue {
                ForEach(items, id: \.id) { ext in
                    ExtensionRow(name: ext.name, isEnabled: enabledIDs.contains(ext.id)) { enabled in
                        setEnabled(enabled, for: ext.id)
                    }
                    .tag(ext.id)
                    // Leading inset matches the Key Bindings rows' `rowInset`.
                    .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                    .listRowSeparator(.hidden)
                }
            }
        }
    }

    private func setEnabled(_ enabled: Bool, for id: String) {
        if enabled { enabledIDs.insert(id) } else { enabledIDs.remove(id) }
        AppSettings.setExtensionEnabled(id, enabled)
    }
}

/// One sidebar row: the extension's name, with a small dot that toggles on its
/// own tap — independent of selecting the row.
///
/// The dot is an overlay, not a member of the row's layout, so it claims no
/// width and the name sits at the same margin it would with no dot at all. It
/// hangs left into the padding the sidebar list already reserves, close enough
/// to read as attached to the name rather than as its own column.
///
/// It is drawn only when the extension is enabled. A green/gray pair encodes
/// the state in hue alone, which is exactly the distinction red-green color
/// blindness loses; presence-vs-absence survives that, and grayscale and low
/// contrast too. The name stays dimmed while disabled so the row carries the
/// state redundantly, and the tap target keeps its size either way, so a
/// disabled extension is still togglable from the sidebar.
private struct ExtensionRow: View {
    let name: String
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Text(name)
            .foregroundStyle(isEnabled ? .primary : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(isEnabled ? Color.green : .clear)
                    .frame(width: 6, height: 6)
                    // A tap target wider than the visible dot, still narrow
                    // enough to stay inside the list's own left padding.
                    .frame(width: 14, height: 18)
                    .contentShape(Rectangle())
                    // Placed in the gutter the row insets leave before the name
                    // (8pt of `listRowInsets` plus the ~7pt a plain List adds of
                    // its own). Measured, not guessed: centering it in that
                    // gutter left only 0.5pt between the dot and the first
                    // letter, so it sits left of center — ~5pt of air after the
                    // dot, and still ~6pt clear of the box border.
                    .offset(x: -13)
                    .onTapGesture { onToggle(!isEnabled) }
                    .accessibilityLabel(isEnabled ? "Enabled" : "Disabled")
                    .accessibilityAddTraits(.isButton)
            }
    }
}

/// One extension's detail pane, top to bottom: name, version line, short
/// description + "Learn more…", action buttons, then a specs block
/// (author/repository/size/last updated).
private struct ExtensionDetailView: View {
    let ext: EdmundExtension
    @Binding var isEnabled: Bool

    @State private var isInstalled: Bool
    @State private var isDownloading = false
    @State private var downloadError: String?
    @State private var showingLongDescription = false

    init(ext: EdmundExtension, isEnabled: Binding<Bool>) {
        self.ext = ext
        self._isEnabled = isEnabled
        self._isInstalled = State(initialValue: ext.isInstalled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ext.name)
                .font(.title2.bold())

            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle")
                if let downloadCount = ext.downloadCount {
                    Text("\(downloadCount)")
                    Text("·")
                }
                Text("v\(ext.version)")
                if isInstalled {
                    Text("(installed v\(ext.version))")
                }
            }
            .foregroundStyle(.secondary)
            .controlSize(.small)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(ext.summary)
                    .fixedSize(horizontal: false, vertical: true)
                if ext.longDescriptionURL != nil {
                    Button("Learn more…") { showingLongDescription = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .controlSize(.small)
                }
            }

            buttonRow

            Spacer().frame(height: 4)

            specs

            Spacer()
        }
        .sheet(isPresented: $showingLongDescription) {
            if let url = ext.longDescriptionURL {
                LongDescriptionSheet(title: ext.name, markdownURL: url)
            }
        }
        // `isInstalled` is a local snapshot so the button group doesn't
        // flicker on every SwiftUI re-evaluation; that snapshot only refreshes
        // on our own download()/uninstall() calls. An install can also finish
        // in the background outside this view (AppSettings.applyExtensionStates
        // re-installing a previously-enabled extension at launch) — catch that
        // by refreshing on the same notification that signals a real change.
        .onReceive(NotificationCenter.default.publisher(for: .mathEngineChanged)) { _ in
            isInstalled = ext.isInstalled
        }
    }

    @ViewBuilder
    private var buttonRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if isInstalled {
                    if ext.hasUpdate {
                        Button("Update") { download() }
                    }
                    Button(isEnabled ? "Disable" : "Enable") { isEnabled.toggle() }
                    Button("Uninstall") { uninstall() }
                } else {
                    Button(isDownloading ? "Downloading…" : "Download") { download() }
                        .disabled(isDownloading)
                }
                if let donateURL = ext.donateURL {
                    Button("Donate") { NSWorkspace.shared.open(donateURL) }
                }
            }
            if let downloadError {
                Text(downloadError)
                    .foregroundStyle(.secondary)
                    .controlSize(.small)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 300, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var specs: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let developer = ext.developer {
                specRow("Author") {
                    if let url = developer.profileURL {
                        Button(developer.name) { NSWorkspace.shared.open(url) }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                    } else {
                        Text(developer.name)
                    }
                }
            }
            if let repo = ext.repositoryURL {
                specRow("Repository") {
                    Button(repo.absoluteString) { NSWorkspace.shared.open(repo) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                }
            }
            if let size = ext.installedSizeDescription {
                specRow("Size") { Text(size) }
            }
            if let lastUpdated = ext.lastUpdated {
                specRow("Last updated") {
                    Text(lastUpdated, format: .relative(presentation: .named))
                }
            }
        }
        .foregroundStyle(.secondary)
        .controlSize(.small)
    }

    @ViewBuilder
    private func specRow(_ label: String, @ViewBuilder value: () -> some View) -> some View {
        HStack(spacing: 4) {
            Text("\(label):")
            value()
        }
    }

    private func download() {
        isDownloading = true
        downloadError = nil
        Task {
            await ext.download()
            isDownloading = false
            if ext.isInstalled {
                isInstalled = true
            } else {
                // Only real extension today; a generic "download failed"
                // would be technically true but less useful here — say why.
                downloadError = RaTeXRelease.isConfigured
                    ? "Download failed. Try again."
                    : "RaTeX isn't available in this build yet."
            }
        }
    }

    private func uninstall() {
        // Disable first: MathRendering would fall back to SwiftMath on its
        // own once the renderer stops reporting ready, but leaving the
        // persisted "enabled" flag set would make a fresh install of the
        // same extension silently come back on.
        if isEnabled { isEnabled = false }
        Task {
            await ext.uninstall()
            isInstalled = ext.isInstalled
        }
    }
}

/// A markdown README fetched from `markdownURL` and rendered in a themed
/// popup webview — reuses Edmund's own Read-mode markdown→HTML pipeline
/// (`ReadModeWebView`) rather than a second, weaker renderer.
private struct LongDescriptionSheet: View {
    let title: String
    let markdownURL: URL
    @State private var markdown: String?
    @State private var loadError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
            Group {
                if let markdown {
                    ReadModeWebViewRepresentable(markdown: markdown)
                } else if let loadError {
                    Text(loadError)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 640, height: 480)
        .task {
            do {
                let (data, _) = try await URLSession.shared.data(from: markdownURL)
                markdown = String(data: data, encoding: .utf8) ?? ""
            } catch {
                loadError = "Couldn't load the description."
            }
        }
    }
}

/// Wraps `ReadModeWebView` (Edmund's own themed, JS-disabled markdown→HTML
/// renderer — already public) for SwiftUI. Mirrors `ContentWidthSlider`'s
/// `NSViewRepresentable` pattern in AppearanceSettingsView.swift.
private struct ReadModeWebViewRepresentable: NSViewRepresentable {
    let markdown: String

    func makeNSView(context: Context) -> ReadModeWebView {
        let view = ReadModeWebView()
        view.render(markdown: markdown, theme: .default, callouts: Callout.defaultStyles)
        return view
    }

    func updateNSView(_ view: ReadModeWebView, context: Context) {
        view.render(markdown: markdown, theme: .default, callouts: Callout.defaultStyles)
    }
}
