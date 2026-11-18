// swift-tools-version: 5.9
import PackageDescription

// QuantKit: models and the network layer of the iOS app. Foundation only, so it also builds and
// tests on Linux (the app target itself needs Xcode).
let package = Package(
    name: "QuantKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "QuantKit", targets: ["QuantKit"])],
    targets: [
        .target(name: "QuantKit"),
        .testTarget(
            name: "QuantKitTests",
            dependencies: ["QuantKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
