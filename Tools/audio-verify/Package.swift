// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "audio-verify",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../../Packages/PlaybackEngine"),
        .package(path: "../../Packages/EscapementCore"),
    ],
    targets: [
        .executableTarget(
            name: "audio-verify",
            dependencies: [
                .product(name: "PlaybackEngine", package: "PlaybackEngine"),
                .product(name: "EscapementCore", package: "EscapementCore"),
            ])
    ]
)
