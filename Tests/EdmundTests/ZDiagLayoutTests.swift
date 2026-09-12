import Testing
import Foundation
@testable import EdmundCore

// TEMPORARY diagnostic — reports (through a deliberately failing expectation,
// which GitHub's check-run summary prints in full) where the bundled Syntaxes
// payload actually lives in the test process. Deleted once known.
@Suite("diag")
struct ZDiagLayoutTests {
    @Test("report bundle layout")
    func reportLayout() {
        let fm = FileManager.default
        var lines: [String] = []
        func dump(_ label: String, _ url: URL?) {
            guard let url else { lines.append("\(label): nil"); return }
            lines.append("\(label): \(url.path)")
            let entries = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
            lines.append("  entries: \(entries.sorted().prefix(30).joined(separator: " | "))")
        }
        dump("main.bundleURL", Bundle.main.bundleURL)
        dump("main.resourceURL", Bundle.main.resourceURL)
        let core = Bundle(for: SyntaxDefinitionStore.self)
        dump("core.bundleURL", core.bundleURL)
        dump("core.resourceURL", core.resourceURL)
        dump("exe", URL(fileURLWithPath: CommandLine.arguments[0]))
        let report = lines.joined(separator: " // ")
        Issue.record("LAYOUT >>> \(report)")
    }
}
