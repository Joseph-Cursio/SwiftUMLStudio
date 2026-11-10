// swift-tools-version: 6.2
import PackageDescription

// Every target builds in the Swift 6 language mode, and a warning in any of them fails the build.
// SwiftPM ignores warning settings for a package built as someone else's dependency, so this
// binds this package's own builds alone.
let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .treatAllWarnings(as: .error)
]

let package = Package(
    name: "SwiftUMLBridge",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SwiftUMLBridgeFramework", targets: ["SwiftUMLBridgeFramework"]),
        .executable(name: "swiftumlbridge", targets: ["swiftumlbridge"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/SourceKitten", from: "0.34.1"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0")
    ],
    targets: [
        .target(
            name: "SwiftUMLBridgeFramework",
            dependencies: [
                .product(name: "SourceKittenFramework", package: "SourceKitten"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ],
            resources: [.copy("Resources/graphre.js")],
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "swiftumlbridge",
            dependencies: [
                "SwiftUMLBridgeFramework",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SwiftUMLBridgeFrameworkTests",
            dependencies: ["SwiftUMLBridgeFramework"],
            resources: [.copy("TestData")],
            swiftSettings: swiftSettings
        ),
        // The CLI is the artifact Homebrew builds and users actually run, but it
        // sat outside every coverage measurement because nothing linked it. Its
        // argument surface — flag precedence, entry-point validation, output
        // routing — is testable without generating a single diagram.
        .testTarget(
            name: "SwiftUMLBridgeCLITests",
            dependencies: ["swiftumlbridge", "SwiftUMLBridgeFramework"],
            swiftSettings: swiftSettings
        )
    ]
)
