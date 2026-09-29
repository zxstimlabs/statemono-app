// swift-tools-version: 6.0
import PackageDescription

// Phase 0 of docs/search-plan.md: measures search on the links and queries in docs/search-test-links.md.
// Not part of either app. Run from this folder: `swift run SearchEval <command>`.
let package = Package(
    name: "SearchEval",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(path: "../../Packages/StatemonoKit"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "SearchEval",
            dependencies: [
                .product(name: "StatemonoKit", package: "StatemonoKit"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
