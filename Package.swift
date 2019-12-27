// swift-tools-version:5.1
import PackageDescription

let package = Package(
  name: "StreamLayerify",
  platforms: [
    .macOS(.v10_14)
  ],
  products: [
    .executable(
      name: "swift-prefixify",
      targets: [
        "StreamLayerify"
      ]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-syntax.git", .revision("0.50100.0")),
    .package(url: "https://github.com/apple/swift-package-manager.git", from: "0.3.0"),
    .package(url: "https://github.com/mxcl/Path.swift", from: "1.0.0-alpha.3")
  ],
  targets: [
    .target(name: "StreamLayerify",
            dependencies: ["SwiftSyntax", "SwiftPM-auto", "Path"],
            path: "Sources/")
  ],
  swiftLanguageVersions: [.version("5")]
)
