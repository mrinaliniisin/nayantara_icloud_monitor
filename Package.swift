// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nayantara",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Nayantara", swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
