// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RpplCore",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .watchOS(.v26),
        .macOS(.v15),
    ],
    products: [
        .library(name: "RpplCore", targets: ["RpplCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.0"),
    ],
    targets: [
        .target(
            name: "RpplCore",
            dependencies: [.product(name: "Yams", package: "Yams")],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "RpplCoreTests",
            dependencies: ["RpplCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
