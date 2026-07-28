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

    // Bottom corners only — the sidebar/detail pair sits flush at the top of
    // the panel (no rounding to clip against there), the footer strip is what
    // gives the panel its rounded bottom.
    private var panelShape: some Shape {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 8,
                               bottomTrailingRadius: 8, topTrailingRadius: 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                List(selection: $selectedID) {
                    sidebarSection("Installed", items: installed, isExpanded: $installedExpanded)
                    sidebarSection("Recommended", items: recommended, isExpanded: $recommendedExpanded)
                }
                .listStyle(.sidebar)
                // `.sidebar` draws a vibrant, accent-tinted material. Hiding the
                // scroll background and painting the shared surface underneath
                // keeps the sidebar's row/selection styling while dropping the
                // tint, so the two halves of the split read as one surface.
                .scrollContentBackground(.hidden)
                .settingsSurfaceBackground()
                .frame(minWidth: 140, idealWidth: 180, maxWidth: 260)

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
                    } else {
                        Text("No extensions installed.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
                .settingsSurfaceBackground()
            }
            // Width matches the other panes (`settingsPanePadding`'s 600), so
            // the window doesn't resize when switching tabs.
            .frame(width: 600, height: 320)

            Divider()

            HStack {
                Spacer()
                Button("More extensions…") {
                    // STUB: link to GitHub extensions repo for now.
                    // Extensions marketplace comes later.
                }
            }
            .padding(10)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .clipShape(panelShape)
        .overlay(panelShape.stroke(Color(nsColor: .separatorColor)))
        .focusEffectDisabled()
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
            .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
            .selectionDisabled()

            if isExpanded.wrappedValue {
                ForEach(items, id: \.id) { ext in
                    ExtensionRow(name: ext.name, isEnabled: enabledIDs.contains(ext.id)) { enabled in
                        setEnabled(enabled, for: ext.id)
                    }
                    .tag(ext.id)
                    .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
                }
            }
        }
    }

    private func setEnabled(_ enabled: Bool, for id: String) {
        if enabled { enabledIDs.insert(id) } else { enabledIDs.remove(id) }
        AppSettings.setExtensionEnabled(id, enabled)
    }
}

/// One sidebar row: a small leading dot that toggles on its own tap —
/// independent of selecting the row — plus the extension's name.
///
/// The dot is drawn only when the extension is enabled. A green/gray pair
/// encodes the state in hue alone, which is exactly the distinction
/// red-green color blindness loses; presence-vs-absence survives it, and
/// survives grayscale and low contrast too. The name stays dimmed while
/// disabled so the row still carries the state redundantly. The tap target
/// keeps its full size either way, so the dot doesn't become a moving target
/// and a disabled extension is still togglable from the sidebar.
private struct ExtensionRow: View {
    let name: String
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isEnabled ? Color.green : .clear)
                .frame(width: 6, height: 6)
                .frame(width: 16, height: 16)   // wider invisible tap target than the visible dot
                .contentShape(Rectangle())
                .onTapGesture { onToggle(!isEnabled) }
                .accessibilityLabel(isEnabled ? "Enabled" : "Disabled")
                .accessibilityAddTraits(.isButton)

            Text(name)
                .foregroundStyle(isEnabled ? .primary : .secondary)
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
