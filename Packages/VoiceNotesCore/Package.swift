// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoiceNotesCore",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "VoiceNotesCore", targets: ["VoiceNotesCore"]),
    ],
    targets: [
        .target(name: "VoiceNotesCore"),
        .testTarget(name: "VoiceNotesCoreTests", dependencies: ["VoiceNotesCore"]),
    ]
)
