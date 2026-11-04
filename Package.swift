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
            url: "https://github.com/Hopcast/hopcast-sdk-ios/releases/download/0.6.0/HopcastKit.xcframework.zip",
            checksum: "7707013e95d7988e32502cd271113e4aa9b272ea151bc8a548deba1bc2f68a0a"
        )
    ]
)
