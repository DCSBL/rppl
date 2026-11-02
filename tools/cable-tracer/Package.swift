// swift-tools-version: 6.2
import PackageDescription

// Internal tool, not shipped: trace and review cable routes on satellite imagery.
// - CableTracerCore: geometry, plausibility checks, priors, training-set export (also builds on Linux).
// - CableTracerUI: the SwiftUI + MapKit editor, shared by the macOS executable and the iOS app
//   in CableTracerApp/ (run in the simulator when the Mac has no screen-recording permission).
// - cable-tracer: macOS executable; also the headless `--export-training-set` command.
let package = Package(
    name: "cable-tracer",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "CableTracerCore", targets: ["CableTracerCore"]),
        .library(name: "CableTracerUI", targets: ["CableTracerUI"]),
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
        .target(
            name: "CableTracerUI",
            dependencies: ["CableTracerCore", .product(name: "RpplCore", package: "RpplCore")]
        ),
        .executableTarget(
            name: "CableTracer",
            dependencies: ["CableTracerCore", "CableTracerUI", .product(name: "RpplCore", package: "RpplCore")]
        ),
        .testTarget(
            name: "CableTracerCoreTests",
            dependencies: ["CableTracerCore"]
        ),
    ]
)
