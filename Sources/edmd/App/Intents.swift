import AppIntents
import AppKit

// MARK: - App Intents (Shortcuts / Spotlight / Finder Quick Actions)
//
// These live in the app target so `openAppWhenRun` runs `perform()` inside the
// live Edmund process, letting them drive `NSDocumentController` directly — the
// same code paths as the launch-argument open (`main.swift`) and the Services
// provider (`ServicesProvider.swift`).
//
// Discovery requires a `Metadata.appintents` bundle inside the app, which Xcode
// generates in a build phase SwiftPM doesn't run; `scripts/build-app.sh`
// invokes `appintentsmetadataprocessor` to produce it. Without that step the
// intents compile but never appear in Shortcuts.

struct OpenInEdmundIntent: AppIntent {
    static let title: LocalizedStringResource = "Open in Edmund"
    static let description = IntentDescription("Opens a Markdown or text file in Edmund.")
    static let openAppWhenRun = true

    @Parameter(title: "File")
    var file: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult {
        // Prefer the file's real on-disk URL so edits save back to the original.
        // Shortcuts may hand back a sandbox-copied URL for some inputs; opening
        // that still works but Save-in-place lands in the copy. We open whatever
        // URL we're given (there's no more-original handle available here) and
        // note it rather than silently substituting a copy.
        guard let url = file.fileURL else {
            throw NSError(domain: "com.i7t5.edmund", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The file has no accessible URL."])
        }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        NSApp.activate(ignoringOtherApps: true)
        return .result()
    }
}

struct NewEdmundDocumentIntent: AppIntent {
    static let title: LocalizedStringResource = "New Edmund Document"
    static let description = IntentDescription("Opens a new Edmund document containing the given text.")
    static let openAppWhenRun = true

    @Parameter(title: "Text", default: "")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult {
        (NSDocumentController.shared as? DocumentController)?.newDocument(withContent: text)
        NSApp.activate(ignoringOtherApps: true)
        return .result()
    }
}

struct EdmundShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenInEdmundIntent(),
                    phrases: ["Open in \(.applicationName)"],
                    shortTitle: "Open in Edmund",
                    systemImageName: "doc.text")
        AppShortcut(intent: NewEdmundDocumentIntent(),
                    phrases: ["New \(.applicationName) document"],
                    shortTitle: "New Document",
                    systemImageName: "square.and.pencil")
    }
}
