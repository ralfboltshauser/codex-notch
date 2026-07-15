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
        .target(name: "CodexNotchCore"),
        .executableTarget(
            name: "CodexNotchApp",
            dependencies: [
                "CodexNotchCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
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
            dependencies: ["CodexNotchCore"]
        ),
        .testTarget(
            name: "CodexNotchTests",
            dependencies: ["CodexNotchApp", "CodexNotchCore"]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
