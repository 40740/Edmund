# macOS integrations: Services, App Intents, Quick Look, AppleScript syntax

Expands [`../ARCHITECTURE.md`](../ARCHITECTURE.md) §6 (feature map). Covers the
OS-level entry points into Edmund added beyond `CFBundleDocumentTypes`
(double-click / Open With), and — importantly — **two limitations that are not
bugs but consequences of how Edmund is built and signed**. Read those before
assuming an integration is broken.

## 1. Why

Edmund is a native editor, so it should be reachable the native ways: from the
right-click Services menu, from Shortcuts/Spotlight, and by pressing Space on a
`.md` in Finder. Three of the four pieces reuse code that already exists — the
Quick Look preview in particular is the app's own `ReadModeWebView`, so a
Finder preview renders identically to Read mode with no second renderer.

## 2. The four pieces

| Piece | Files | Status |
| --- | --- | --- |
| **AppleScript code-fence syntax** | `EdmundCore/Resources/Syntaxes/applescript.json` | Works. Fully tested. |
| **Services menu** | `edmd/App/ServicesProvider.swift`, `NSServices` in `Info.plist`, registered in `main.swift` `applicationDidFinishLaunching` | Built & registered; live menu-click not yet exercised. |
| **App Intents** | `edmd/App/Intents.swift` (+ `DocumentController.newDocument(withContent:)`) | Code correct; **Shortcuts discovery blocked** — see §3. |
| **Quick Look preview** | `EdmundQuickLook` target, `Resources/QuickLookInfo.plist`, `Resources/QuickLook.entitlements`, assembled by `scripts/build-app.sh` | Code + packaging + signing done; **live launch blocked** — see §4. |

Shared plumbing:

- **Services** and the **App Intents** both open documents through the existing
  paths: `NSDocumentController.openDocument(withContentsOf:)` (same call the
  launch-arg open uses in `main.swift`) and a new
  `DocumentController.newDocument(withContent:)` that seeds a fresh untitled doc
  via `Document.pendingContent` (consumed in `Document.showWindows()`). One
  helper, two call sites, so they can't drift.
- **AppleScript syntax** needs no code: `SyntaxDefinitionStore.loadBundled()`
  globs `Resources/Syntaxes/*.json`, so a new language is one file. Word-list
  scopes (`keywords`/`commands`/`types`/…) must be **pairwise disjoint** — the
  scanner's "most specific wins" rule is ambiguous otherwise (a test asserts
  this).
- **Quick Look** hosts `ReadModeWebView` in a `QLPreviewingController`. The web
  view derives light/dark from `effectiveAppearance` and re-renders on a system
  appearance flip, so the preview follows System Settings ▸ Appearance for
  free. `preparePreviewOfFile(at:)` awaits the first render (via
  `onLoadFinished`) so Quick Look snapshots the finished page, not a blank one.
  Body font is `EditorTheme.quickLook` = system-ui (`HTMLTheme.cssFontStack`
  gained a `system-ui` keyword branch), rather than the editor's serif.

## 3. Limitation — App Intents don't appear in Shortcuts from a SwiftPM build

The intents compile and are correct, but **Shortcuts/Spotlight won't list them**
when the app is built with SwiftPM.

Shortcuts discovers intents from a `Metadata.appintents` bundle inside the app.
Xcode generates it in a build phase; SwiftPM has no equivalent.
`appintentsmetadataprocessor` (the tool that produces the bundle) needs per-file
`.swiftconstvalues` supplementary outputs from the Swift compiler, or it fails
with `No swift const values found … BinaryScanningError error 6`. Xcode requests
those outputs via `SWIFT_ENABLE_EMIT_CONST_VALUES`; SwiftPM does not, and
passing `-const-gather-protocols-file` alone does **not** populate the
output-file-map with const-values entries, so nothing is emitted. Confirmed
2026-07-23 against Xcode 16.2.

`build-app.sh` runs the metadata step best-effort: it prints a one-line warning
and continues, and will start succeeding automatically the day the toolchain can
emit the const values (or the app is built from an Xcode project).

**What still works:** the **Services** entries deliver the same "Open in Edmund"
/ "New Document with Selection" actions with no metadata dependency. If Shortcuts
support becomes a requirement, the fix is an Xcode-project build (or a wrapper
target), not more SwiftPM flags.

## 4. Limitation — the Quick Look appex doesn't launch under ad-hoc signing

The extension is complete and registers with `pluginkit` (enabled, content type
matches), but **`quicklookd` silently declines to launch it** when the app is
ad-hoc signed and run from a dev / non-`/Applications` location: no logs from the
extension, no `amfid`/`pkd` rejection trace — Quick Look just falls back to the
system plain-text preview (raw monospace source).

Proof it's the signing/location and not the code: MarkEdit's **Developer-ID**
appex in `/Applications` *is* invoked by the same `qlmanage -p`; a copy of ours
with a unique bundle id (dodging the `com.i7t5.edmund` collision from multiple
dev builds) was still never launched. Edmund signs ad-hoc (`codesign --sign -`,
no Team ID); app extensions are held to a stricter launch bar than the host app.

**To verify live:** Developer-ID sign + notarize + install to `/Applications`,
then press Space on a `.md` in Finder. `os_log` breadcrumbs in
`PreviewViewController` (`loadView`, `preparePreviewOfFile`, `render finished`)
are visible under `subsystem == "com.i7t5.edmund.quicklook"`:

```bash
log show --last 1m --predicate 'subsystem == "com.i7t5.edmund.quicklook"'
```

Do **not** overwrite the user's live `/Applications/Edmund.app` just to test —
ask first. The render code is the same `ReadModeWebView` that renders correctly
in-app, so the only unproven link is WKWebView drawing inside the appex sandbox.

### Signing order in `build-app.sh` (why it's the way it is)

The appex is sealed inside the app, so it must be signed **before** the app, and
the app must be sealed **without** `--deep` — a `--deep` outer sign re-signs
every nested item with default flags, which strips the appex's sandbox
entitlements and resets its identifier to the app's. So: sign
`Sparkle.framework` (deep, for its own XPC helpers) → sign the appex with its
entitlements → seal the `.app` non-deep over the already-signed contents. The
appex's resource bundles go in `Contents/Resources` *before* signing (an appex's
`Bundle.module` resolves via `Bundle.main.resourceURL`), unlike the app's
SwiftMath bundle which must sit at the `.app` root *after* the seal.

## 5. Not built (candidates)

- **App `.sdef` scripting dictionary** — real `tell application "Edmund" to …`
  automation; the one surface App Intents can't cover. Distinct from §2's
  AppleScript *highlighting*.
- **Conversion intents** — "Markdown to HTML/PDF" reusing `MarkdownPrinter` /
  `DocumentHTML`; cheap once §3's metadata plumbing works.
- **`UTImportedTypeDeclarations`** — declare `net.daringfireball.markdown`
  properly (consistent Finder kind string + doc icon); also modernizes the
  legacy `CFBundleTypeExtensions` block. Pure `Info.plist`.
- **CLI symlink**, **Dock menu** (`applicationDockMenu`), **Quick Look
  thumbnails** (`QLThumbnailProvider`, same appex).
