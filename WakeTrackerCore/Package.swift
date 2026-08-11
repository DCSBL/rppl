// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WakeTrackerCore",
    platforms: [
        .iOS(.v26),
        .watchOS(.v26),
        .macOS(.v15),
    ],
    products: [
        .library(name: "WakeTrackerCore", targets: ["WakeTrackerCore"]),
    ],
    targets: [
        .target(name: "WakeTrackerCore"),
        .testTarget(
            name: "WakeTrackerCoreTests",
            dependencies: ["WakeTrackerCore"]
        ),
    ]
)
