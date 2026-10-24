import SwiftUI

extension View {
    /// Uploads reading positions after page turns and when the app goes
    /// to the background, so other devices see your place, and keeps sites
    /// current.
    func syncTriggers() -> some View {
        modifier(SyncTriggers())
    }
}

/// Split out so the values it watches don't redraw the root view.
private struct SyncTriggers: ViewModifier {
    @Environment(ProgressStore.self) private var progress
    @Environment(ServerSync.self) private var sync
    @Environment(SiteUpdates.self) private var siteUpdates
    @Environment(ServerStore.self) private var servers
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: progress.pendingUploads) {
                sync.scheduleUpload()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    Task { await sync.uploadPending() }
                } else {
                    // Back in the app is when new versions of sites are
                    // looked for, a few times a day at most.
                    Task { await siteUpdates.checkAll() }
                }
            }
            .onChange(of: servers.signedOut) {
                // A library just signed in to, or added, is checked too.
                Task { await siteUpdates.checkAll() }
            }
            .task {
                // Places saved while offline go up at launch.
                await sync.uploadPending()
                await siteUpdates.checkAll()
            }
    }
}
