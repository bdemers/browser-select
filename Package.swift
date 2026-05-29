// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BrowserSelect",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        // Pure-Swift core: no AppKit imports so it stays headlessly testable.
        .target(
            name: "BrowserSelectKit"
        ),
        // The accessory app: AppKit/SwiftUI glue around the kit.
        .executableTarget(
            name: "BrowserSelectApp",
            dependencies: ["BrowserSelectKit"]
        ),
        .testTarget(
            name: "BrowserSelectKitTests",
            dependencies: ["BrowserSelectKit"]
        )
    ]
)
