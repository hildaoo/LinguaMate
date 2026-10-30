// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LinguaMateCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "LinguaMateCore", targets: ["LinguaMateCore"])],
    targets: [
        .target(name: "LinguaMateCore", resources: [.process("Resources")]),
        .testTarget(name: "LinguaMateCoreTests", dependencies: ["LinguaMateCore"])
    ]
)
