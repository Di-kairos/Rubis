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
        // Чтение метаданных (SPEC §5.3) — тот же SFBAudioEngine, что и в
        // PlaybackEngine; внешняя зависимость из разрешённой тройки §3.2.
        .package(url: "https://github.com/sbooth/SFBAudioEngine.git", from: "0.9.1"),
    ],
    targets: [
        .target(
            name: "MusicLibrary",
            dependencies: [
                .product(name: "EscapementCore", package: "EscapementCore"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SFBAudioEngine", package: "SFBAudioEngine"),
            ]),
        .testTarget(name: "MusicLibraryTests", dependencies: ["MusicLibrary"]),
    ]
)
