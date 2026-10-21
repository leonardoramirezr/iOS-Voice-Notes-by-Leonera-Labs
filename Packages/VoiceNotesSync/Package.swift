// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoiceNotesSync",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "VoiceNotesSync", targets: ["VoiceNotesSync"]),
    ],
    dependencies: [
        // Same sync engine as the official Simplenote iOS app. Always pin a release tag: the binary is
        // downloaded from the release that the manifest of the resolved revision names.
        .package(url: "https://github.com/Simperium/simperium-ios", exact: "1.9.2"),
        .package(path: "../VoiceNotesCore"),
    ],
    targets: [
        .target(
            name: "VoiceNotesSync",
            dependencies: [
                .product(name: "Simperium", package: "simperium-ios"),
                .product(name: "VoiceNotesCore", package: "VoiceNotesCore"),
            ]
        ),
        .testTarget(
            name: "VoiceNotesSyncTests",
            dependencies: [
                "VoiceNotesSync",
                .product(name: "Simperium", package: "simperium-ios"),
                .product(name: "VoiceNotesCore", package: "VoiceNotesCore"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
