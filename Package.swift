// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HotDock",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "HotDock",
            path: "Sources/HotDock",
            // Swift 5 language mode: this app is single-threaded AppKit/SwiftUI UI code and
            // takes C callbacks (CGEventTap) that Swift 6 strict concurrency cannot reason about.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
