// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "NtfyCodexOverlay",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "NtfyCodexOverlay", targets: ["NtfyCodexOverlay"])
    ],
    targets: [
        .executableTarget(name: "NtfyCodexOverlay"),
        .testTarget(
            name: "NtfyCodexOverlayTests",
            dependencies: ["NtfyCodexOverlay"]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
