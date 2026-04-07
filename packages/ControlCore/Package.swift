// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ControlCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "ControlCore", targets: ["ControlCore"]),
    ],
    dependencies: [
        .package(path: "../SharedModels"),
    ],
    targets: [
        .target(
            name: "ControlCore",
            dependencies: ["SharedModels"]
        ),
        .testTarget(
            name: "ControlCoreTests",
            dependencies: ["ControlCore"]
        ),
    ]
)
