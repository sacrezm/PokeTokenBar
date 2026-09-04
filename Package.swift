// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PokeForge",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PokeForge", targets: ["PokeTokenBar"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
    ],
    targets: [
        .executableTarget(
            name: "PokeTokenBar",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/PokeTokenBar",
            linkerSettings: [.linkedLibrary("sqlite3"),
                             .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "PokeTokenBarTests",
            dependencies: ["PokeTokenBar"],
            path: "Tests/PokeTokenBarTests",
            resources: [
                .copy("Fixtures/CodexFork"),
                .copy("Fixtures/CodexSubagent"),
            ]
        ),
    ]
)
