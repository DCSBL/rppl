// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "example-session-compiler",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../../RpplCore"),
    ],
    targets: [
        .executableTarget(
            name: "example-session-compiler",
            dependencies: [.product(name: "RpplCore", package: "RpplCore")]
        ),
    ]
)
