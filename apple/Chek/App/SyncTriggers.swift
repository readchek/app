import SwiftUI

extension View {
    /// Uploads reading positions after page turns and when the app goes
    /// to the background, so other devices see your place.
    func syncTriggers() -> some View {
        modifier(SyncTriggers())
    }
}

/// Split out so the values it watches don't redraw the root view.
private struct SyncTriggers: ViewModifier {
    @Environment(ProgressStore.self) private var progress
    @Environment(ServerSync.self) private var sync
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: progress.pendingUploads) {
                sync.scheduleUpload()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    Task { await sync.uploadPending() }
                }
            }
            .task {
                // Places saved while offline go up at launch.
                await sync.uploadPending()
            }
    }
}
