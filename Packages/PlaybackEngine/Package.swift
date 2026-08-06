// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlaybackEngine",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PlaybackEngine", targets: ["PlaybackEngine"])
    ],
    dependencies: [
        .package(path: "../EscapementCore")
    ],
    targets: [
        .target(
            name: "PlaybackEngine",
            dependencies: [.product(name: "EscapementCore", package: "EscapementCore")]),
        .testTarget(name: "PlaybackEngineTests", dependencies: ["PlaybackEngine"]),
    ]
)
