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
        // Форк: 0.13.0 + DSD256 в SFBDSFDecoder (апстрим принимает DSF только
        // DSD64/128, хотя DoP умеет DSD256; S23). Точный тег — `from:` взял бы
        // непропатченную апстримную версию из тегов форка.
        .package(url: "https://github.com/Di-kairos/SFBAudioEngine.git", exact: "0.13.0-rubis.1"),
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
