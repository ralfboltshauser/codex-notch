// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CodexNotch",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexNotch", targets: ["CodexNotchApp"]),
        .executable(name: "CodexNotchHook", targets: ["CodexNotchHook"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4"),
    ],
    targets: [
        .target(
            name: "CodexNotchCore",
            path: "apps/macos/Sources/CodexNotchCore"
        ),
        .executableTarget(
            name: "CodexNotchApp",
            dependencies: [
                "CodexNotchCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "apps/macos/Sources/CodexNotchApp",
            resources: [
                .copy("Resources/Sounds"),
                .copy("Resources/Changelog.json"),
            ],
            linkerSettings: [
                .linkedFramework("Network"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
        ),
        .executableTarget(
            name: "CodexNotchHook",
            dependencies: ["CodexNotchCore"],
            path: "apps/macos/Sources/CodexNotchHook"
        ),
        .testTarget(
            name: "CodexNotchTests",
            dependencies: ["CodexNotchApp", "CodexNotchCore"],
            path: "apps/macos/Tests/CodexNotchTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
