// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TeroCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TeroCore", targets: ["TeroCore"])],
    targets: [
        .target(name: "TeroCore", path: "Sources/Core"),
        .testTarget(name: "TeroCoreTests", dependencies: ["TeroCore"], path: "Tests")
    ]
)
