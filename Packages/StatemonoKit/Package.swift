// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatemonoKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "StatemonoKit", targets: ["StatemonoKit"]),
    ],
    targets: [
        .target(name: "StatemonoKit"),
        .testTarget(name: "StatemonoKitTests", dependencies: ["StatemonoKit"]),
    ]
)
