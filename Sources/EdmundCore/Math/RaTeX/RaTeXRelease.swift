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
    ///
    /// 0.1.14 is the first release the Advanced Math extension can ship on: it
    /// closes both of the layout gaps that blocked it. `renderLatex` gained a
    /// `displayMode` argument (upstream PR #134), so inline math finally
    /// typesets inline; and `aligned` now expands row spacing to fit tall rows
    /// — measured on the repro from
    /// `docs/investigations/math-ratex-multirow-investigation.md`, a 3-row
    /// `\lim`/`\frac`/`\exp` derivation went from height 1.6 / depth 1.1 em
    /// with its rows collapsed into a 1.57em band (0.1.12) to height 4.15 /
    /// depth 3.65 em with three cleanly separated rows at a ~2.7em pitch.
    public static let version = "0.1.14"
    public static let archiveURL = URL(string: "https://github.com/I7T5/Edmund/releases/download/ratex-wasm-assets-0.1.14/ratex-wasm-0.1.14.tar.gz")!
    /// Lowercase hex SHA-256 of the pinned `.tar.gz`, verified against the
    /// hosted asset (not just the local build) before pinning.
    public static let archiveSHA256 = "283e3f8ea8d11e9b339518c657ff8642235adaaf2f1ef22149313f2bb5e690f8"

    /// Whether a real artifact hash has been pinned.
    public static var isConfigured: Bool { !archiveSHA256.isEmpty }
}
