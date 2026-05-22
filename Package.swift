// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "envchain",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "envchain",
            targets: ["envchain"]
        )
    ],
    targets: [
        .executableTarget(
            name: "envchain",
            path: "Sources/envchain"
        ),
        .testTarget(
            name: "envchainTests",
            path: "Tests/envchainTests"
        )
    ]
)
