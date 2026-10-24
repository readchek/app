import ChekReader
import SwiftData
import SwiftUI

@main
struct ChekApp: App {
    private let app: AppDependencies
    private let notifications: NotificationOpener
    @Environment(\.scenePhase) private var scenePhase

    init() {
        ReaderFormats.registerDefaults()
        // The server says how long its answers stay good, and series,
        // chapters and covers change rarely, so a cache far larger than the
        // system's default keeps screens instant on a second visit.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 1 << 30)
        do {
            app = AppDependencies(container: try .chek())
        } catch {
            // Every version of the store is migrated by ChekMigrationPlan,
            // so failing here means the device's storage is unusable.
            fatalError("Couldn't open the library: \(error)")
        }
        FollowRefresh.register(follows: app.follows)
        notifications = NotificationOpener(router: app.router)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .appEnvironment(app)
                .task { await app.library.carryOverChibiMangaLibrary() }
        }
        .modelContainer(app.container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                FollowRefresh.schedule()
            }
        }
    }
}

/// The stores the whole app shares, created once at launch.
///
/// Views take the store they need from the environment, so previews can
/// hand them in-memory versions.
@MainActor
final class AppDependencies {
    let container: ModelContainer
    let router: AppRouter
    let library: LibraryStore
    let progress: ProgressStore
    let readerSettings: ReaderSettings
    let servers: ServerStore
    let sync: ServerSync
    let follows: FollowStore
    let downloads: Downloads

    init(container: ModelContainer, defaults: UserDefaults = .standard) {
        self.container = container
        router = AppRouter()
        library = LibraryStore(context: container.mainContext)
        progress = ProgressStore(context: container.mainContext)
        readerSettings = ReaderSettings(defaults: defaults)
        servers = ServerStore(context: container.mainContext)
        sync = ServerSync(servers: servers, progress: progress, context: container.mainContext)
        follows = FollowStore(context: container.mainContext, servers: servers)
        downloads = Downloads(servers: servers)
        servers.onRemove = { [downloads] account in
            downloads.removeAll(for: account)
            SeriesCache.removeAll(for: account)
        }
    }
}

extension View {
    /// Puts each of the app's stores in the environment.
    func appEnvironment(_ app: AppDependencies) -> some View {
        self
            .environment(app.router)
            .environment(app.library)
            .environment(app.progress)
            .environment(app.readerSettings)
            .environment(app.servers)
            .environment(app.sync)
            .environment(app.follows)
            .environment(app.downloads)
    }
}
