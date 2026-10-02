// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "stria",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "StriaCore", targets: ["StriaCore"]),
    .executable(name: "stria", targets: ["StriaCLI"]),
    .executable(name: "stria-app", targets: ["StriaApp"])
  ],
  dependencies: [
    .package(
      url: "https://github.com/tacogips/agent-gateway.git",
      revision: "c7f269753ec36aca92d429ec13316ba033128967"
    )
  ],
  targets: [
    .target(
      name: "StriaCore",
      dependencies: [
        .product(name: "AgentGateway", package: "agent-gateway"),
        .product(name: "AgentGatewayAppCore", package: "agent-gateway"),
        .product(name: "ACP", package: "agent-gateway")
      ],
      resources: [.copy("Resources/ProviderModels.json")]
    ),
    .executableTarget(name: "StriaCLI", dependencies: ["StriaCore"]),
    // The app runs as a bare SwiftPM executable. The embedded Info.plist
    // gives it the name "Stria" in the menu bar and Dock instead of the
    // executable name.
    .executableTarget(
      name: "StriaApp",
      dependencies: ["StriaCore"],
      linkerSettings: [
        .unsafeFlags(
          ["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Resources/StriaInfo.plist"],
          .when(platforms: [.macOS])
        )
      ]
    ),
    .testTarget(name: "StriaCoreTests", dependencies: ["StriaCore"])
  ],
  swiftLanguageModes: [.v6]
)
