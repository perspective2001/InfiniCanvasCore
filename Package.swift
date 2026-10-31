// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InfiniCanvasCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "InfiniCanvasCore", targets: ["InfiniCanvasCore"])
    ],
    targets: [
        .target(name: "InfiniCanvasCore", path: "Sources/InfiniCanvasCore")
    ]
)
