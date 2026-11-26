// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "HopcastKit",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "HopcastKit", targets: ["HopcastKit"])
    ],
    targets: [
        .binaryTarget(
            name: "HopcastKit",
            url: "https://github.com/Hopcast/hopcast-sdk-ios/releases/download/0.7.0/HopcastKit.xcframework.zip",
            checksum: "8fcf9a595840eb820c297d5260f0dcb12d1fa58f9fbe2cf4e45d8c62caa7b702"
        )
    ]
)
