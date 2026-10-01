// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "KaibaViewer",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "KaibaViewerCore", targets: ["KaibaViewerCore"]),
    .executable(name: "kaiba-viewer", targets: ["KaibaViewerCLI"])
  ],
  targets: [
    .target(name: "KaibaViewerCore"),
    .executableTarget(
      name: "KaibaViewerCLI",
      dependencies: ["KaibaViewerCore"]
    ),
    .testTarget(
      name: "KaibaViewerCoreTests",
      dependencies: ["KaibaViewerCore"]
    )
  ],
  swiftLanguageModes: [.v6]
)
