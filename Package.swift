// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Glint",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "GlintCore", targets: ["GlintCore"]),
    .executable(name: "Glint", targets: ["Glint"]),
    .executable(name: "glint-bench", targets: ["GlintBench"]),
  ],
  targets: [
    .systemLibrary(name: "CZlib"),
    .target(name: "GlintCore", dependencies: ["CZlib"]),
    .executableTarget(name: "Glint", dependencies: ["GlintCore"]),
    .executableTarget(name: "GlintBench", dependencies: ["GlintCore"]),
    .testTarget(name: "GlintCoreTests", dependencies: ["GlintCore", "CZlib"]),
    .testTarget(name: "GlintTests", dependencies: ["Glint", "GlintCore"]),
  ],
  swiftLanguageModes: [.v6]
)
