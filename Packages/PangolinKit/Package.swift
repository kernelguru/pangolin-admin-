// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PangolinKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PangolinKit", targets: ["PangolinKit"]),
        .library(name: "PangolinSSH", targets: ["PangolinSSH"]),
        .library(name: "PangolinUpdater", targets: ["PangolinUpdater"])
    ],
    dependencies: [
        // Apple's official SSH implementation (no third-party forks): certificate auth,
        // Secure Enclave keys, exec channels.
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.15.1"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        // 5.x needs a newer Swift than Xcode 26.3 ships.
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0" ..< "5.0.0")
    ],
    targets: [
        /// REST client for the Pangolin Integration API.
        .target(name: "PangolinKit"),

        /// Minimal SSH client: certificate/public-key auth, pinned host keys, exec with streamed output.
        .target(
            name: "PangolinSSH",
            dependencies: [
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),

        /// Pure logic for updating a Pangolin Docker deployment (compose parsing, version lookup, scripts).
        .target(name: "PangolinUpdater"),

        .testTarget(name: "PangolinKitTests", dependencies: ["PangolinKit"]),
        .testTarget(name: "PangolinSSHTests", dependencies: ["PangolinSSH"]),
        .testTarget(name: "PangolinUpdaterTests", dependencies: ["PangolinUpdater"])
    ]
)
