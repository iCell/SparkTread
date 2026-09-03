// swift-tools-version: 6.0
// SparkTread — headless package: pure simulation, application workflows, and CLI tools.
//
// `Sources/AppleAdapters` is deliberately NOT a target here. It imports SpriteKit and
// SwiftUI and is compiled by the Xcode app target generated from `project.yml`, together
// with `App/` and `PixelProduction/Runtime/`. Keeping it out of the package is what makes
// `swift build` work on a machine with only the Swift command line tools.

import PackageDescription

/// Swift 6 language mode is pinned for every target so concurrency and Sendable checking
/// stay uniform between the package and the Xcode app target.
let swift6 = SwiftSetting.swiftLanguageMode(.v6)

let package = Package(
    name: "SparkTread",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "GameCore", targets: ["GameCore"]),
        .library(name: "GameApplication", targets: ["GameApplication"]),
        .executable(name: "ContentValidator", targets: ["ContentValidator"]),
    ],
    targets: [
        // Deterministic simulation. No dependencies at all — not even Foundation.
        .target(
            name: "GameCore",
            path: "Sources/GameCore",
            swiftSettings: [swift6]
        ),
        // Session flow, replay, content loading. Depends inward on GameCore only.
        .target(
            name: "GameApplication",
            dependencies: ["GameCore"],
            path: "Sources/GameApplication",
            swiftSettings: [swift6]
        ),
        // Offline content linting for CI and authoring.
        .executableTarget(
            name: "ContentValidator",
            dependencies: ["GameApplication"],
            path: "Tools/ContentValidator",
            swiftSettings: [swift6]
        ),
        .testTarget(
            name: "GameCoreTests",
            dependencies: ["GameCore"],
            path: "Tests/GameCoreTests",
            swiftSettings: [swift6]
        ),
        .testTarget(
            name: "GameApplicationTests",
            dependencies: ["GameApplication"],
            path: "Tests/GameApplicationTests",
            swiftSettings: [swift6]
        ),
    ]
)
