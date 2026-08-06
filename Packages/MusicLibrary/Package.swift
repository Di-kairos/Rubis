// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MusicLibrary",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MusicLibrary", targets: ["MusicLibrary"])
    ],
    dependencies: [
        .package(path: "../EscapementCore")
    ],
    targets: [
        .target(
            name: "MusicLibrary",
            dependencies: [.product(name: "EscapementCore", package: "EscapementCore")]),
        .testTarget(name: "MusicLibraryTests", dependencies: ["MusicLibrary"]),
    ]
)
