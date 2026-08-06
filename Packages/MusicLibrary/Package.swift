// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MusicLibrary",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MusicLibrary", targets: ["MusicLibrary"])
    ],
    dependencies: [
        .package(path: "../EscapementCore"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "MusicLibrary",
            dependencies: [
                .product(name: "EscapementCore", package: "EscapementCore"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]),
        .testTarget(name: "MusicLibraryTests", dependencies: ["MusicLibrary"]),
    ]
)
