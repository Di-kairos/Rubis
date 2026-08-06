// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EscapementCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "EscapementCore", targets: ["EscapementCore"])
    ],
    targets: [
        .target(name: "EscapementCore"),
        .testTarget(name: "EscapementCoreTests", dependencies: ["EscapementCore"]),
    ]
)
