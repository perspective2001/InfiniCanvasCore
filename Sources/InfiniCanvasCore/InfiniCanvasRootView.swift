import SwiftUI

/// Stable public entry point for the permanent Swift Playgrounds host app.
/// Keep private implementation details inside the versioned package.
public struct InfiniCanvasRootView: View {
    @StateObject private var workspace = CanvasStore()
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        ContentView()
            .environmentObject(workspace)
            // Fill the scene explicitly. A PKCanvasView has no intrinsic view
            // size; relying on it to size a root ZStack can render a blank host.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.991, green: 0.984, blue: 0.961))
            .preferredColorScheme(.light)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active {
                    workspace.endLectureRecording()
                    workspace.saveImmediately()
                }
            }
    }
}
