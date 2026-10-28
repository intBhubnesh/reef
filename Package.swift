// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "reef",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ReefCore", targets: ["ReefCore"]),
        .executable(name: "reef-bridge", targets: ["ReefBridge"]),
        .executable(name: "reef-app", targets: ["ReefApp"]),
    ],
    targets: [
        .target(name: "ReefCore"),
        .executableTarget(name: "ReefBridge", dependencies: ["ReefCore"]),
        .executableTarget(
            name: "ReefApp",
            dependencies: ["ReefCore"],
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .testTarget(name: "ReefCoreTests", dependencies: ["ReefCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
