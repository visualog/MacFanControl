// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RemoteProtocol",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "RemoteProtocol", targets: ["RemoteProtocol"]),
    ],
    dependencies: [
        .package(path: "../SharedModels"),
    ],
    targets: [
        .target(
            name: "RemoteProtocol",
            dependencies: ["SharedModels"]
        ),
        .testTarget(
            name: "RemoteProtocolTests",
            dependencies: ["RemoteProtocol"]
        ),
    ]
)
