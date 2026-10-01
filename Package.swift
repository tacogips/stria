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
      ]
    ),
    .executableTarget(name: "StriaCLI", dependencies: ["StriaCore"]),
    .executableTarget(name: "StriaApp", dependencies: ["StriaCore"]),
    .testTarget(name: "StriaCoreTests", dependencies: ["StriaCore"])
  ],
  swiftLanguageModes: [.v6]
)
