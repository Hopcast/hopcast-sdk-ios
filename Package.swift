// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "HopcastKit",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "HopcastKit", targets: ["HopcastKit"])
    ],
    targets: [
        .binaryTarget(name: "HopcastKit", path: "HopcastKit.xcframework")
    ]
)
