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
            ],
            exclude: ["Info.plist"],
            linkerSettings: [
                // Вшитый Info.plist: без NSMicrophoneUsageDescription TCC молча
                // запрещает захват входа даже для loopback-устройства.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/audio-verify/Info.plist",
                ])
            ])
    ]
)
