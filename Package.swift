// swift-tools-version:6.0
import Foundation
import PackageDescription

let gitVersion: String = {
  let pipe = Pipe()
  let proc = Process()
  proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
  proc.arguments = ["describe", "--tags", "--always"]
  proc.standardOutput = pipe
  proc.standardError = FileHandle.nullDevice
  try? proc.run()
  proc.waitUntilExit()
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  return String(data: data, encoding: .utf8)?
    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "dev"
}()

let package = Package(
  name: "envchain",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(
      name: "envchain",
      targets: ["envchain"]
    )
  ],
  dependencies: [
    .package(
      url: "https://github.com/apple/swift-argument-parser", from: "1.0.0")
  ],
  targets: [
    .target(
      name: "CVersion",
      path: "Sources/CVersion",
      cSettings: [
        .unsafeFlags(["-DENVCHAIN_VERSION=\"\(gitVersion)\""])
      ]
    ),
    .systemLibrary(
      name: "CLibSecret",
      path: "Sources/CLibSecret",
      pkgConfig: "libsecret-1",
      providers: [
        .apt(["libsecret-1-dev"])
      ]
    ),
    .executableTarget(
      name: "envchain",
      dependencies: [
        .target(name: "CVersion"),
        .target(name: "CLibSecret", condition: .when(platforms: [.linux])),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources/envchain"
    ),
    .testTarget(
      name: "envchainTests",
      path: "Tests/envchainTests"
    ),
  ]
)
