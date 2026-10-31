// swift-tools-version: 5.9
// Continuous-integration twin of the real permanent Swift Playgrounds host.
// Only dependency locator differs: checkout-local path tests current PR source.
// Do not install this fixture on an iPad in place of the user's existing app.
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "InfiniCanvasPermanent",
    platforms: [.iOS("17.5")],
    products: [
        .iOSApplication(
            name: "Infini Canvas",
            targets: ["AppModule"],
            bundleIdentifier: "com.perspective2001.infini-canvas.native",
            displayVersion: "0.9.0",
            bundleVersion: "6",
            appIcon: .placeholder(icon: .pencil),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [.pad],
            supportedInterfaceOrientations: [.landscapeLeft, .landscapeRight, .portrait],
            capabilities: [
                .microphone(purposeString: "Record lectures only when you press Record and connect audio to handwritten notes.")
            ]
        )
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            dependencies: [.product(name: "InfiniCanvasCore", package: "InfiniCanvasCore")],
            path: "Sources"
        )
    ]
)
