// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InfiniCanvasCore",
    platforms: [.iOS("17.5")],
    products: [
        .library(name: "InfiniCanvasCore", targets: ["InfiniCanvasCore"])
    ],
    targets: [
        .target(name: "InfiniCanvasCore", path: "Sources/InfiniCanvasCore"),
        .testTarget(name: "InfiniCanvasCoreTests", dependencies: ["InfiniCanvasCore"], path: "Tests/InfiniCanvasCoreTests")
    ]
)
