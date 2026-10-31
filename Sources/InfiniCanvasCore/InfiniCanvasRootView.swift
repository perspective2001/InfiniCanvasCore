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
            .preferredColorScheme(.light)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active {
                    workspace.endLectureRecording()
                    workspace.saveImmediately()
                }
            }
    }
}
