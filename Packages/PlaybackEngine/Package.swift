// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlaybackEngine",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PlaybackEngine", targets: ["PlaybackEngine"])
    ],
    dependencies: [
        .package(path: "../EscapementCore"),
        .package(url: "https://github.com/sbooth/SFBAudioEngine.git", from: "0.9.1"),
        .package(url: "https://github.com/sbooth/CAAudioHardware.git", from: "0.7.1"),
    ],
    targets: [
        .target(
            name: "PlaybackEngine",
            dependencies: [
                .product(name: "EscapementCore", package: "EscapementCore"),
                .product(name: "SFBAudioEngine", package: "SFBAudioEngine"),
                .product(name: "CAAudioHardware", package: "CAAudioHardware"),
            ]),
        .testTarget(name: "PlaybackEngineTests", dependencies: ["PlaybackEngine"]),
    ]
)
