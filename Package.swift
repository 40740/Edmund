// swift-tools-version: 6.0
import PackageDescription

// The module split below is deliberate, and the reason is the Quick Look appex.
//
// `EdmundCore` is the *editor*: AppKit + TextKit 2, the extension host, the
// syntax highlighter, the WebKit-based Read-mode renderer, the RaTeX/WASM math
// host. A Quick Look preview needs almost none of that — it needs to turn
// markdown into HTML with the same pipeline the app's Read mode uses so the
// preview and the editor agree on what a document looks like.
//
// Linking all of `EdmundCore` into the appex meant a Space-bar preview started a
// process that imported the entire editor (and SwiftMath's math fonts, and the
// extension host) before it could draw anything — and put every heavy framework
// in the path of a preview extension that Quick Look is watching for
// responsiveness ("扩展在预览此文稿期间失败", issue #8). So the shared rendering
// pipeline lives in two small modules with a narrow dependency surface:
//
//   EdmundMarkdown — pure parsing / model / HTML generation (no AppKit).
//   EdmundRender   — + HTML theme, math rasterization, asset inlining.
//   EdmundCore     — the editor and everything that depends on it.
//
// The app uses all three; the appex uses the first two.
let package = Package(
    name: "Edmund",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.5.0"),
        .package(url: "https://github.com/mgriebling/SwiftMath.git", from: "1.7.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Parsing + the markdown model + the HTML body renderer + the syntax
        // definitions. No AppKit: this is the half a preview can use as-is.
        .target(
            name: "EdmundMarkdown",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            resources: [.copy("Resources/Syntaxes")]),
        // The rest of the Read-mode pipeline: theme CSS, math rasterization
        // (SwiftMath), local-image inlining, and the complete-page assembler.
        .target(
            name: "EdmundRender",
            dependencies: [
                "EdmundMarkdown",
                .product(name: "SwiftMath", package: "SwiftMath"),
            ]),
        // The editor. Depends on the rendering pipeline, not the other way round.
        .target(
            name: "EdmundCore",
            dependencies: ["EdmundMarkdown", "EdmundRender"]),
        // The user-facing app is "Edmund" (CFBundleName); the executable target —
        // and so the Mach-O binary at Edmund.app/Contents/MacOS/edmd — is "edmd",
        // an expansion of "Editor for Markdown". A quiet backronym for anyone who
        // peeks inside the bundle or runs `swift run edmd`.
        .executableTarget(
            name: "edmd",
            dependencies: ["EdmundCore", .product(name: "Sparkle", package: "Sparkle")]),
        // The Quick Look preview extension. Built as an executable target but
        // packaged as an `.appex` by build-app.sh; its entry point is
        // Foundation's NSExtensionMain, redirected via the linker `-e` flag
        // (SwiftPM has no first-class app-extension product type).
        // `-fapplication-extension` (the `-application_extension` marker) is what
        // makes the linked binary refuse to use APIs that are unavailable to app
        // extensions, and — more to the point here — what makes the result a
        // *real* extension to anything that inspects it. Without it an appex can
        // be rejected before its principal class is ever asked for a view.
        .executableTarget(
            name: "EdmundQuickLook",
            dependencies: ["EdmundRender"],
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-e", "-Xlinker", "_NSExtensionMain",
                "-Xlinker", "-fapplication-extension",
            ])]),
        .testTarget(
            name: "EdmundTests",
            dependencies: ["EdmundCore", "EdmundMarkdown", "EdmundRender", "edmd"]),
    ]
)
