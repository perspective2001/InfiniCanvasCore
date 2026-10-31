import SwiftUI
import InfiniCanvasCore

// CI twin of the user's unmodified permanent app entry point.
@main
struct InfiniCanvasApp: App {
    var body: some Scene {
        WindowGroup {
            InfiniCanvasRootView()
        }
    }
}
