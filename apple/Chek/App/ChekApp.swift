import ChekReader
import SwiftData
import SwiftUI

@main
struct ChekApp: App {
    private let app: AppDependencies

    init() {
        ReaderFormats.registerDefaults()
        do {
            app = AppDependencies(container: try .chek())
        } catch {
            // Every version of the store is migrated by ChekMigrationPlan,
            // so failing here means the device's storage is unusable.
            fatalError("Couldn't open the library: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .appEnvironment(app)
        }
        .modelContainer(app.container)
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

    init(container: ModelContainer, defaults: UserDefaults = .standard) {
        self.container = container
        router = AppRouter()
        library = LibraryStore(context: container.mainContext)
        progress = ProgressStore(context: container.mainContext)
        readerSettings = ReaderSettings(defaults: defaults)
        servers = ServerStore(context: container.mainContext)
        sync = ServerSync(servers: servers, progress: progress, context: container.mainContext)
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
    }
}
