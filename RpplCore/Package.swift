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
        // Linux only: Apple's Compression framework has no Linux equivalent, so raw DEFLATE
        // falls back to system zlib (see RawDeflate.swift). Unused on Apple platforms.
        .systemLibrary(
            name: "CZlib",
            providers: [.apt(["zlib1g-dev"])]
        ),
        .target(
            name: "RpplCore",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                .target(name: "CZlib", condition: .when(platforms: [.linux])),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "RpplCoreTests",
            dependencies: ["RpplCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
