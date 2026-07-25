// The Clear Version History popup: browse macOS Auto Save versions grouped by
// folder → file → version, and clear them (by selection or older than a date),
// with filename/path search. See EdmundCore/Model/VersionHistory.swift for the model.

import SwiftUI
import AppKit
import EdmundCore

/// Recent + currently-open document URLs, deduped, existing files only.
@MainActor
private func candidateDocumentURLs() -> [URL] {
    var urls = NSDocumentController.shared.recentDocumentURLs
    for doc in NSDocumentController.shared.documents {
        if let u = doc.fileURL { urls.append(u) }
    }
    var seen = Set<URL>()
    return urls.filter { FileManager.default.fileExists(atPath: $0.path) && seen.insert($0).inserted }
}

private enum CheckState { case on, off, mixed }

struct VersionHistoryView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var folders: [FolderNode] = []
    @State private var query = ""
    @State private var selection: Set<URL> = []      // selected version ids
    @State private var beforeDate = Date()
    @State private var scannedURLs: [URL] = []
    @State private var isLoading = false
    @State private var refreshToken = 0

    @State private var pendingTargets: [VersionInfo] = []
    @State private var confirmClear = false
    @State private var errorMessage: String?

    private var displayed: [FolderNode] { filterVersionTree(folders, query: query) }
    private var allInfos: [VersionInfo] { folders.flatMap { $0.files.flatMap { $0.versions.map(\.info) } } }
    private var selectedInfos: [VersionInfo] { allInfos.filter { selection.contains($0.id) } }
    private var totalSize: Int64 { allInfos.reduce(0) { $0 + $1.size } }
    private var selectedSize: Int64 { selectedInfos.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            toolbar
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 720, height: 560)
        .task(id: refreshToken) { await reload() }
        .confirmationDialog(
            "Delete \(pendingTargets.count) version\(pendingTargets.count == 1 ? "" : "s")?",
            isPresented: $confirmClear, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { performRemove(pendingTargets) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently deletes the selected saved versions. It can't be undone.")
        }
        .alert("Couldn't delete some versions",
               isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text("Version History").font(.headline)
                Text("Auto Save keeps past versions of your documents. Review and delete them to reclaim disk space. Only documents Edmund knows about are shown — use Scan Folder to add more.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search filename or path", text: $query)
                .textFieldStyle(.plain)
            Spacer()
            Button { scanFolder() } label: { Label("Scan Folder…", systemImage: "folder.badge.plus") }
            Button { refreshToken += 1 } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh")
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    @ViewBuilder private var content: some View {
        if isLoading {
            centered { ProgressView() }
        } else if displayed.isEmpty {
            centered {
                Text(folders.isEmpty ? "No version history found for these documents."
                                     : "No matches.")
                    .foregroundStyle(.secondary)
            }
        } else {
            List {
                ForEach(displayed) { folder in
                    DisclosureGroup {
                        ForEach(folder.files) { file in
                            DisclosureGroup {
                                ForEach(file.versions) { v in versionRow(v) }
                            } label: { fileRow(file) }
                        }
                    } label: { folderRow(folder) }
                }
            }
            .listStyle(.inset)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack {
                DatePicker("Delete versions before", selection: $beforeDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .fixedSize()
                Button("Delete Before Date…") {
                    confirm(versions(olderThan: beforeDate, in: allInfos))
                }
                .disabled(allInfos.allSatisfy { $0.date >= beforeDate })
                Spacer()
            }
            HStack {
                Text("Selected: \(byteString(selectedSize))").foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
                Text("Total: \(byteString(totalSize))").foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                Button("Delete Selected…") { confirm(selectedInfos) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection.isEmpty)
            }
        }
        .padding(16)
    }

    // MARK: Rows

    private func folderRow(_ folder: FolderNode) -> some View {
        let all = folder.files.flatMap { $0.versions.map(\.id) }
        return row(check: checkState(all),
                   toggle: { toggle(all) },
                   icon: "folder",
                   title: folder.name,
                   subtitle: folder.displayPath,
                   size: folder.size)
    }

    private func fileRow(_ file: FileNode) -> some View {
        let ids = file.versions.map(\.id)
        return row(check: checkState(ids),
                   toggle: { toggle(ids) },
                   icon: "doc.text",
                   title: file.name,
                   subtitle: "\(file.versions.count) version\(file.versions.count == 1 ? "" : "s")",
                   size: file.size)
    }

    private func versionRow(_ v: VersionNode) -> some View {
        row(check: selection.contains(v.id) ? .on : .off,
            toggle: { toggle([v.id]) },
            icon: "clock",
            title: v.date.formatted(date: .abbreviated, time: .shortened),
            subtitle: nil,
            size: v.size)
    }

    private func row(check: CheckState, toggle: @escaping () -> Void,
                     icon: String, title: String, subtitle: String?, size: Int64) -> some View {
        HStack(spacing: 8) {
            checkbox(check, toggle)
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
            }
            Spacer()
            Text(byteString(size)).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func checkbox(_ s: CheckState, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: s == .on ? "checkmark.square.fill"
                            : s == .mixed ? "minus.square.fill" : "square")
                .foregroundStyle(s == .off ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    private func centered<V: View>(@ViewBuilder _ v: () -> V) -> some View {
        VStack { Spacer(); v(); Spacer() }.frame(maxWidth: .infinity)
    }

    // MARK: Selection

    private func checkState(_ ids: [URL]) -> CheckState {
        let n = ids.filter(selection.contains).count
        return n == 0 ? .off : (n == ids.count ? .on : .mixed)
    }

    private func toggle(_ ids: [URL]) {
        if checkState(ids) == .on { selection.subtract(ids) } else { selection.formUnion(ids) }
    }

    // MARK: Actions

    private func reload() async {
        isLoading = true
        let urls = Array(Set(candidateDocumentURLs() + scannedURLs))
        let infos = await Task.detached { VersionHistoryStore.gather(urls: urls) }.value
        folders = buildVersionTree(infos)
        selection.formIntersection(Set(infos.map(\.id)))   // drop ids that no longer exist
        isLoading = false
    }

    private func confirm(_ targets: [VersionInfo]) {
        guard !targets.isEmpty else { return }
        pendingTargets = targets
        confirmClear = true
    }

    private func performRemove(_ targets: [VersionInfo]) {
        Task {
            let errors = await Task.detached { VersionHistoryStore.remove(targets) }.value
            selection.subtract(targets.map(\.id))
            if !errors.isEmpty { errorMessage = errors.first?.localizedDescription }
            refreshToken += 1
        }
    }

    private func scanFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Scan"
        panel.message = "Choose a folder to scan for Markdown files with version history"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        Task {
            let found = await Task.detached { VersionHistoryStore.scanFolder(dir) }.value
            scannedURLs = Array(Set(scannedURLs + found))
            refreshToken += 1
        }
    }
}

private func byteString(_ n: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
}
