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
    targets: [
        .target(
            name: "RpplCore",
            dependencies: [
                // Apple platforms use Compression; Linux CI links system zlib.
                .target(name: "CZlib", condition: .when(platforms: [.linux])),
            ],
            resources: [.process("Resources")]
        ),
        .systemLibrary(
            name: "CZlib",
            path: "Sources/CZlib",
            pkgConfig: "zlib",
            providers: [
                .apt(["zlib1g-dev"]),
                .brew(["zlib"]),
            ]
        ),
        .testTarget(
            name: "RpplCoreTests",
            dependencies: ["RpplCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
