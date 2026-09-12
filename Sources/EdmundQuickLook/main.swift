import Foundation
import EdmundCore

// This target is an `.appex` bundle: its real entry point is Foundation's
// `NSExtensionMain`, wired via the `-e _NSExtensionMain` linker flag in
// Package.swift. Its top-level code is never reached in the appex itself — the
// linker redirects the entry symbol before `main` — so this file exists mostly
// to satisfy SwiftPM's requirement that an executable target has an entry point.
//
// The one thing that must happen *before* `NSExtensionMain` runs is pointing the
// diagnostic log at the app's log directory. A preview that renders wrong is
// otherwise undiagnosable: the extension's own print/os_log output goes to a
// unified-log stream nobody can be asked to open, while `Log` already knows how
// to append a readable file the user can just send. Configuring it here means a
// failed preview leaves its reason on disk (see `PreviewViewController`, which
// logs every step and the degraded-render outcome).
//
// `main.swift` is used (rather than an `@main` type) precisely because this is
// top-level code: it runs during static initialization of the module, which the
// redirect of `main`-to-`_NSExtensionMain` doesn't touch.
extension Log {
    /// Appends to the same `~/.edmund/logs/edmund-<date>.log` the app writes, so
    /// an app-then-preview reproduction lands in one file. Best-effort: a log
    /// directory that can't be created must not stop the preview.
    static func configureForQuickLook() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".edmund/logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Log.configure(enabled: true, directory: directory, retention: 7 * 24 * 60 * 60)
    }
}

Log.configureForQuickLook()
Log.info("Quick Look extension loaded", category: .app)
