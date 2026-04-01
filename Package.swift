// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "md",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MarkdownEditorCore"),
        .executableTarget(
            name: "MarkdownEditor",
            dependencies: ["MarkdownEditorCore"]),
        .testTarget(
            name: "MarkdownEditorTests",
            dependencies: ["MarkdownEditorCore"]),
    ]
)
