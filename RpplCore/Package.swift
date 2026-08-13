// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RpplCore",
    platforms: [
        .iOS(.v26),
        .watchOS(.v26),
        .macOS(.v15),
    ],
    products: [
        .library(name: "RpplCore", targets: ["RpplCore"]),
    ],
    targets: [
        .target(name: "RpplCore"),
        .testTarget(
            name: "RpplCoreTests",
            dependencies: ["RpplCore"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
