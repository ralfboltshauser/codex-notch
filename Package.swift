// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CodexNotch",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexNotch", targets: ["CodexNotchApp"]),
        .executable(name: "CodexNotchHook", targets: ["CodexNotchHook"]),
    ],
    targets: [
        .target(name: "CodexNotchCore"),
        .executableTarget(
            name: "CodexNotchApp",
            dependencies: ["CodexNotchCore"],
            linkerSettings: [
                .linkedFramework("Network"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "CodexNotchHook",
            dependencies: ["CodexNotchCore"]
        ),
        .testTarget(
            name: "CodexNotchTests",
            dependencies: ["CodexNotchApp", "CodexNotchCore"]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
