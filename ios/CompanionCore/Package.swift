// swift-tools-version: 5.9
import PackageDescription

let package = Package(name: "CompanionCore", platforms: [.macOS(.v12), .iOS(.v14)],
  products: [.library(name: "CompanionCore", targets: ["CompanionCore"])],
  targets: [.target(name: "CompanionCore"),
    .testTarget(name: "CompanionCoreTests", dependencies: ["CompanionCore"])])
