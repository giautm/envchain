// swift-tools-version:6.0
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
            path: "Sources/envchain",
            plugins: [.plugin(name: "VersionPlugin")]
        ),
        .executableTarget(
            name: "generate-version",
            path: "Sources/generate-version"
        ),
        .plugin(
            name: "VersionPlugin",
            capability: .buildTool(),
            dependencies: ["generate-version"]
        ),
        .testTarget(
            name: "envchainTests",
            path: "Tests/envchainTests"
        )
    ]
)
