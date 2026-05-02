// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Maestro",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "maestro-cli", targets: ["MaestroCLI"]),
    .executable(name: "Maestro", targets: ["MaestroApp"]),
    .executable(name: "maestro-core-checks", targets: ["MaestroCoreChecks"]),
    .library(name: "MaestroCore", targets: ["MaestroCore"]),
    .library(name: "MaestroAutomation", targets: ["MaestroAutomation"])
  ],
  targets: [
    .target(name: "MaestroCore"),
    .target(
      name: "MaestroAutomation",
      dependencies: ["MaestroCore"]
    ),
    .executableTarget(
      name: "MaestroCLI",
      dependencies: ["MaestroCore", "MaestroAutomation"]
    ),
    .executableTarget(
      name: "MaestroApp",
      dependencies: ["MaestroCore", "MaestroAutomation"]
    ),
    .executableTarget(
      name: "MaestroCoreChecks",
      dependencies: ["MaestroCore", "MaestroAutomation"]
    )
  ]
)
