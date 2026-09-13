import Foundation

// This target is an `.appex` bundle: its real entry point is Foundation's
// `NSExtensionMain`, wired via the `-e _NSExtensionMain` linker flag in
// Package.swift. Its top-level code is never reached in the appex itself — the
// linker redirects the entry symbol before `main` — so this file exists mostly
// to satisfy SwiftPM's requirement that an executable target has an entry point.
//
// It deliberately imports nothing but Foundation: everything the preview renders
// comes out of `EdmundRender` → `EdmundMarkdown` (see `PreviewViewController`),
// which is the same HTML pipeline the app's Read mode uses. It used to import
// `EdmundCore` — the whole editor, the extension host, the WebKit read view and
// the math rasterizer — purely to write two log lines, and pulled all of that
// into the preview process on the Space-bar path.
//
// Logging setup (which used to live here) is now done on first use inside
// `Diagnostics`, so a preview that fails still leaves a readable reason in
// `~/.edmund/logs/edmund-<date>.log` without any work at process start.
