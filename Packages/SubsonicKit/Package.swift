// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SubsonicKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SubsonicKit", targets: ["SubsonicKit"])
    ],
    dependencies: [
        .package(path: "../EscapementCore")
    ],
    targets: [
        .target(
            name: "SubsonicKit",
            dependencies: [.product(name: "EscapementCore", package: "EscapementCore")]),
        .testTarget(name: "SubsonicKitTests", dependencies: ["SubsonicKit"]),
    ]
)
