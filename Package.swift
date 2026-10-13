// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nayantara",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Update checks; off until the user turns them on (Updater.swift).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "Nayantara",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            // build.sh copies Sparkle.framework into Contents/Frameworks; Xcode
            // would add this search path itself, SwiftPM doesn't.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ]
)
