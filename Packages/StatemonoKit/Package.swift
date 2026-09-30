// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatemonoKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "StatemonoKit", targets: ["StatemonoKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "StatemonoKit",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            // Accelerate's current CBLAS interface, for Smart Search's model (`BertEmbedder`).
            swiftSettings: [.unsafeFlags(["-Xcc", "-DACCELERATE_NEW_LAPACK"])]
        ),
        .testTarget(name: "StatemonoKitTests", dependencies: ["StatemonoKit"]),
    ]
)
