import Testing
@testable import EdmundCore

@Suite("ExtensionRegistry")
struct ExtensionRegistryTests {

    @Test("Advanced Math is registered and not installed before its payload is downloaded")
    @MainActor func advancedMathListed() {
        let ext = ExtensionRegistry.all.first { $0.id == "advanced-math" }
        #expect(ext != nil)
        #expect(ext?.name == "Advanced Math")
        // Nothing in this suite calls download() on the shared instance (that's
        // a real network fetch — see RaTeXWasmIntegrationTests, gated on
        // RATEX_ARCHIVE), so it stays not-installed here regardless of whether
        // RaTeXRelease.isConfigured is true.
        #expect(ext?.isInstalled == false)
        #expect(ext?.mathRenderer != nil)
    }

    @Test("Advanced Math's mathRenderer is the RaTeX engine, not SwiftMath")
    @MainActor func advancedMathProvidesRaTeX() {
        let ext = AdvancedMathExtension.shared
        #expect(ext.mathRenderer?.id == ext.renderer.id)
        #expect(ext.mathRenderer?.id.hasPrefix("ratex@") == true)
    }

    @Test("Advanced Math's version is Edmund's own packaging version, not RaTeX's")
    @MainActor func advancedMathVersioning() {
        let ext = AdvancedMathExtension.shared
        #expect(ext.version == "1.0.0")
        #expect(ext.summary.split(separator: " ").count <= 30)
    }

    @Test("Advanced Math's metadata fields are honest about what's actually known")
    @MainActor func advancedMathMetadata() {
        let ext = AdvancedMathExtension.shared
        #expect(ext.developer?.name == "I7T5")
        #expect(ext.developer?.profileURL != nil)
        #expect(ext.installedSizeDescription != nil)
        #expect(ext.lastUpdated != nil)
        // No dedicated extension repo/README/analytics/donate source exists
        // yet — these must stay nil rather than fabricate data.
        #expect(ext.repositoryURL == nil)
        #expect(ext.longDescriptionURL == nil)
        #expect(ext.downloadCount == nil)
        #expect(ext.donateURL == nil)
        // No update-checking source exists yet.
        #expect(ext.hasUpdate == false)
    }
}
