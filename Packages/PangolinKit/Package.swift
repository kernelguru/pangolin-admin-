// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PangolinKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PangolinKit", targets: ["PangolinKit"])
    ],
    targets: [
        .target(name: "PangolinKit"),
        .testTarget(name: "PangolinKitTests", dependencies: ["PangolinKit"])
    ]
)
