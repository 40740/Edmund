// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "md",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.5.0"),
    ],
    targets: [
        .target(
            name: "MarkdownEditorCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ]),
        .executableTarget(
            name: "MarkdownEditor",
            dependencies: ["MarkdownEditorCore"]),
        .testTarget(
            name: "MarkdownEditorTests",
            dependencies: ["MarkdownEditorCore"]),
    ]
)
