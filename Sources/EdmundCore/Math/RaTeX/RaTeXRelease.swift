import Foundation

/// Pinned RaTeX (KaTeX-compatible, MIT) release coordinates. Never "latest" —
/// a specific version is baked in so an update requires a new app build (and a
/// fresh SHA-256 pin), never a moving target.
///
/// The runtime payload is a single `.tar.gz` bundling the `ratex-wasm` module
/// (`ratex_wasm_bg.wasm` + `ratex_wasm.js` glue) and the KaTeX `.ttf` fonts
/// RaTeX's display list references, unpacked to:
///   `ratex_wasm_bg.wasm`, `ratex_wasm.js`, `fonts/KaTeX_*.ttf`
/// Built deterministically by `scripts/build-ratex-payload.sh` and mirrored as
/// an asset on an Edmund GitHub release (not an app release — a separate,
/// non-`v*` tag so it doesn't trigger `release.yml`) rather than depending on
/// npm/upstream uptime.
public enum RaTeXRelease {
    /// Tracks the upstream RaTeX release the payload was built from.
    public static let version = "0.1.12"
    public static let archiveURL = URL(string: "https://github.com/I7T5/Edmund/releases/download/ratex-wasm-assets-0.1.12/ratex-wasm-0.1.12.tar.gz")!
    /// Lowercase hex SHA-256 of the pinned `.tar.gz`, verified against the
    /// hosted asset (not just the local build) before pinning.
    public static let archiveSHA256 = "e7e1f1c6826125df0a8ad494736211630d6d50733a511cb25f34ba4812d7c232"

    /// Whether a real artifact hash has been pinned.
    public static var isConfigured: Bool { !archiveSHA256.isEmpty }
}
