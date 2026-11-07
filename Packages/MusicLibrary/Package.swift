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
        // Форк: 0.13.0 + DSD256 в SFBDSFDecoder (апстрим принимает DSF только
        // DSD64/128, хотя DoP умеет DSD256; S23). Точный тег — `from:` взял бы
        // непропатченную апстримную версию из тегов форка.
        .package(url: "https://github.com/Di-kairos/SFBAudioEngine.git", exact: "0.13.0-rubis.1"),
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
