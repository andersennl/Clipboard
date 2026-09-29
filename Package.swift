// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Clipboard",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Clipboard", targets: ["Clipboard"])
    ],
    targets: [
        .executableTarget(
            name: "Clipboard",
            path: "Sources/Clipboard"
        ),
        .testTarget(
            name: "ClipboardTests",
            dependencies: ["Clipboard"],
            path: "Tests/ClipboardTests"
        )
    ]
)
