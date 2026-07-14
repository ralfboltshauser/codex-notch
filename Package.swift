// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CodexNotch",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4"),
    ],
    products: [
        .executable(name: "CodexNotch", targets: ["CodexNotchApp"]),
        .executable(name: "CodexNotchHook", targets: ["CodexNotchHook"]),
    ],
    targets: [
        .target(name: "CodexNotchCore"),
        .executableTarget(
            name: "CodexNotchApp",
            dependencies: [
                "CodexNotchCore",
                .product(name: "Sparkle", package: "Sparkle"),
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
