// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SMCBridge",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "SMCBridge", targets: ["SMCBridge"]),
    ],
    dependencies: [
        .package(path: "../SharedModels"),
    ],
    targets: [
        .target(
            name: "SMCBridge",
            dependencies: ["SharedModels"]
        ),
        .testTarget(
            name: "SMCBridgeTests",
            dependencies: ["SMCBridge"]
        ),
    ]
)
