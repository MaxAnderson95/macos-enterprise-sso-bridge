// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "EnterpriseSSOBridge",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "BridgeCore", targets: ["BridgeCore"]),
    .executable(name: "enterprise-sso-bridge", targets: ["EnterpriseSSOBridge"]),
  ],
  targets: [
    .target(name: "BridgeCore"),
    .executableTarget(name: "EnterpriseSSOBridge", dependencies: ["BridgeCore"]),
    .testTarget(name: "BridgeCoreTests", dependencies: ["BridgeCore"]),
  ]
)
