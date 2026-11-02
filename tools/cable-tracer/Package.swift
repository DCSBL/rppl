// swift-tools-version: 6.2
import PackageDescription

// Internal tool, not shipped: a macOS app to trace and review cable routes on satellite imagery,
// plus a pure-Swift core (geometry, plausibility checks, training-set export) that also builds on Linux.
let package = Package(
    name: "cable-tracer",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CableTracerCore", targets: ["CableTracerCore"]),
        .executable(name: "cable-tracer", targets: ["CableTracer"]),
    ],
    dependencies: [
        .package(path: "../../RpplCore"),
    ],
    targets: [
        .target(
            name: "CableTracerCore",
            dependencies: [.product(name: "RpplCore", package: "RpplCore")]
        ),
        .executableTarget(
            name: "CableTracer",
            dependencies: ["CableTracerCore", .product(name: "RpplCore", package: "RpplCore")]
        ),
        .testTarget(
            name: "CableTracerCoreTests",
            dependencies: ["CableTracerCore"]
        ),
    ]
)
