import Testing
import Foundation
import CryptoKit
import AppKit
@testable import EdmundCore

// End-to-end RaTeX wasm test, gated on a local payload archive so it can run on
// a dev machine without shipping the 1 MB artifact into the repo/CI. Set
// `RATEX_ARCHIVE` to the `ratex-wasm-<v>.tar.gz` path to exercise the real
// installer-unpack → JSCore-host → DisplayList-render path. Skipped (passes with
// no assertions) when the env var is unset.
@Suite("RaTeX — wasm integration (gated on RATEX_ARCHIVE)")
struct RaTeXWasmIntegrationTests {

    private var archiveURL: URL? {
        ProcessInfo.processInfo.environment["RATEX_ARCHIVE"].map { URL(fileURLWithPath: $0) }
    }
    private func sha256(_ d: Data) -> String {
        SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }
    private var black: NSColor { NSColor(red: 0, green: 0, blue: 0, alpha: 1) }

    @Test("Unpack, load, and render inline + display math with real metrics")
    @MainActor func endToEnd() async throws {
        guard let archiveURL else { return }   // skipped without the local payload
        let data = try Data(contentsOf: archiveURL)

        let installer = RaTeXInstaller()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ratex-it-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await installer.installAtomically(archive: data, sha256: sha256(data), into: dir)

        // Files unpacked to the expected layout.
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("ratex_wasm_bg.wasm").path))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("ratex_wasm.js").path))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("fonts/KaTeX_Math-Italic.ttf").path))

        let host = WasmMathHost()
        host.load(dir: dir)
        #expect(host.isLoaded)

        // Inline `x^2`: renders, positive size, ascent+descent == image height.
        let inline = host.render(latex: "x^2", displayMode: false, pointSize: 16, color: black)
        #expect(inline != nil)
        if let m = inline {
            #expect(m.image.size.width > 0 && m.image.size.height > 0)
            #expect(abs((m.ascent + m.descent) - m.image.size.height) < 0.01)
        }

        // Display environment that SwiftMath handles differently — must render.
        let display = host.render(latex: "\\begin{aligned} a&=1 \\\\ b&=2 \\end{aligned}",
                                  displayMode: true, pointSize: 18, color: black)
        #expect(display != nil)

        // Garbage LaTeX returns nil (→ per-equation fallback to SwiftMath).
        let bad = host.render(latex: "\\frac{", displayMode: false, pointSize: 16, color: black)
        #expect(bad == nil)

        // Unload clears readiness.
        host.unload()
        #expect(!host.isLoaded)
    }
}
