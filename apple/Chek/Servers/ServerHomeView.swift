import SwiftData
import SwiftUI

/// What's on one server: where you are in it on any device, what's new,
/// and its libraries.
struct ServerHomeView: View {
    let account: UUID
    @Environment(ServerStore.self) private var servers
    @State private var model: ServerHomeModel?
    @State private var editing: ServerEdit?

    var body: some View {
        Group {
            if let server = servers.account(account) {
                ServerHomeContent(account: server, model: model)
                    .navigationTitle(server.name)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Menu("More", systemImage: "ellipsis") {
                                ServerActions(account: server, editing: $editing)
                            }
                        }
                    }
                    .serverEditing($editing)
            } else {
                EmptyState("Library Removed", systemImage: "building.columns")
            }
        }
        // Signing back in loads the home again, rather than leaving what
        // failed while signed out on screen.
        .task(id: LoadKey(account: account, isSignedIn: servers.state(of: account) == .signedIn)) {
            let model = model ?? ServerHomeModel(account: account, servers: servers)
            self.model = model
            await model.load()
        }
    }

    private struct LoadKey: Hashable {
        var account: UUID
        var isSignedIn: Bool
    }
}

/// Loads a server's home in one go, so the sections appear together.
@MainActor
@Observable
final class ServerHomeModel {
    struct Content: Equatable {
        var continueReading: [RemotePublication]
        /// Where you are in each of ``continueReading`` as the server keeps
        /// it, for books this device hasn't opened.
        var serverStatuses: [Int64: ReadingStatus]
        /// Installed extensions, or nil on a server too old to have them.
        var sources: [ChekAPI.InstalledExtension]?
        var recentlyAdded: [RemotePublication]
        var libraries: [ChekAPI.Library]
    }

    private(set) var state: LoadState<Content> = .idle
    /// Why the last refresh failed while content from before still shows.
    private(set) var staleError: DisplayError?
    private let account: UUID
    private let servers: ServerStore

    init(account: UUID, servers: ServerStore) {
        self.account = account
        self.servers = servers
    }

    func load() async {
        if state.value == nil {
            state = .loading
        }
        let account = account
        do {
            let content = try await servers.request(account) { client throws(ChekError) in
                // They load side by side. `async let` loses the error
                // type, so it's restored for the store to see sign-outs.
                do {
                    async let libraries = client.libraries()
                    async let recent = client.recentlyAdded(cursor: nil)
                    async let reading = client.continueReading()
                    async let sources = client.installedExtensionsIfSupported()
                    // The demo account is shared, so what it's "reading"
                    // is other people's; your own places are on the device.
                    let readingItems = account == DemoMode.accountID ? [] : try await reading
                    return try await Content(
                        continueReading: readingItems.map { RemotePublication($0.publication, server: account) },
                        serverStatuses: Dictionary(readingItems.map { item in
                            let progress = item.progress.locator?.locations.totalProgression
                            return (item.publication.id, ReadingStatus(progress: progress, finished: false, opened: true))
                        }, uniquingKeysWith: { first, _ in first }),
                        sources: sources,
                        recentlyAdded: recent.items.map { RemotePublication($0, server: account) },
                        libraries: libraries
                    )
                } catch let error as ChekError {
                    throw error
                } catch {
                    throw .invalidResponse
                }
            }
            state = .loaded(content)
            staleError = nil
            await ServerHomeSnapshot(content).write(for: account)
        } catch {
            // What the server said last time stands in when it can't be
            // reached, so its libraries and sources stay reachable and
            // downloaded chapters can be read offline.
            if state.value == nil, let snapshot = await ServerHomeSnapshot.read(for: account) {
                state = .loaded(snapshot.content(server: account))
                staleError = DisplayError(error)
            } else if state.value == nil {
                state = .failed(DisplayError(error))
            } else {
                staleError = DisplayError(error)
            }
        }
    }
}

/// What a server's screen last showed, kept between launches.
nonisolated private struct ServerHomeSnapshot: Codable {
    var continueReading: [RemotePublication]
    var serverProgress: [Int64: Double?]
    var sources: [ChekAPI.InstalledExtension]?
    var recentlyAdded: [RemotePublication]
    var libraries: [ChekAPI.Library]

    init(_ content: ServerHomeModel.Content) {
        continueReading = content.continueReading
        serverProgress = content.serverStatuses.mapValues(\.progress)
        sources = content.sources
        recentlyAdded = content.recentlyAdded
        libraries = content.libraries
    }

    func content(server: UUID) -> ServerHomeModel.Content {
        ServerHomeModel.Content(
            continueReading: continueReading,
            serverStatuses: serverProgress.mapValues { ReadingStatus(progress: $0, finished: false, opened: true) },
            sources: sources,
            recentlyAdded: recentlyAdded,
            libraries: libraries
        )
    }

    private static func url(for server: UUID) -> URL {
        URL.cachesDirectory.appending(path: "Servers/\(server.uuidString)/home.json")
    }

    @concurrent
    static func read(for server: UUID) async -> ServerHomeSnapshot? {
        guard let data = try? Data(contentsOf: url(for: server)) else { return nil }
        return try? JSONDecoder().decode(ServerHomeSnapshot.self, from: data)
    }

    @concurrent
    func write(for server: UUID) async {
        let url = Self.url(for: server)
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

private struct ServerHomeContent: View {
    let account: ServerAccount
    let model: ServerHomeModel?
    @Environment(ServerStore.self) private var servers
    @Environment(AppRouter.self) private var router
    @Environment(Downloads.self) private var downloads
    @Query private var states: [RemoteReadingState]

    init(account: ServerAccount, model: ServerHomeModel?) {
        self.account = account
        self.model = model
        _states = Query(filter: RemoteReadingState.onServer(account.id))
    }

    var body: some View {
        if servers.state(of: account.id) == .signedOut {
            let kept = downloads.comics(on: account.id)
            ScrollView {
                VStack(spacing: Metrics.sectionSpacing) {
                    EmptyState(
                        "Signed Out",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text("Sign in to \(account.name) again to keep reading.")
                    ) {
                        Button("Sign In") {
                            router.sheet = .signIn(account.id)
                        }
                    }
                    .frame(minHeight: kept.isEmpty ? 480 : 320)
                    if !kept.isEmpty {
                        // What's on the device needs no session.
                        Shelf(title: "Downloaded", items: kept.map { servers.item($0, status: ReadingStatuses(states)[$0.id]) })
                    }
                }
            }
        } else {
            switch model?.state ?? .idle {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.large)
            case .failed(let error):
                FailureState(error: error) {
                    await model?.load()
                }
            case .loaded(let content):
                let statuses = ReadingStatuses(states)
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                        if let error = model?.staleError {
                            StaleNotice(error: error)
                        }
                        if !content.continueReading.isEmpty {
                            Shelf(
                                title: "Continue Reading",
                                items: content.continueReading.map { servers.item($0, status: statuses[$0.id, or: content.serverStatuses[$0.id]]) },
                                isFeatured: true
                            )
                        }
                        if !content.recentlyAdded.isEmpty {
                            Shelf(title: "Recently Added", items: content.recentlyAdded.map { servers.item($0, status: statuses[$0.id]) })
                        }
                        let kept = downloads.comics(on: account.id)
                        if !kept.isEmpty {
                            // Comics kept on the device, there to open
                            // whether or not the server answers.
                            Shelf(title: "Downloaded", items: kept.map { servers.item($0, status: statuses[$0.id, or: content.serverStatuses[$0.id]]) })
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            SectionHeader(title: "Collections")
                            if content.libraries.isEmpty {
                                // A reader starts with no libraries until
                                // the admin shares some, which the server
                                // can't say more about.
                                Text("Nothing here yet. Ask whoever shares \(account.name) with you to give you access.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, Metrics.margin)
                                    .padding(.top, 4)
                            }
                            ForEach(content.libraries) { library in
                                NavigationRow(
                                    title: library.name,
                                    systemImage: "books.vertical",
                                    value: Route.serverLibrary(account.id, library),
                                    showsDivider: library.id != content.libraries.last?.id
                                )
                            }
                        }
                        // The sample library can't add sites, so an empty
                        // section there would lead nowhere.
                        if let sources = content.sources, !(sources.isEmpty && account.id == DemoMode.accountID) {
                            SourcesSection(account: account.id, sources: sources)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .animation(.default, value: model?.staleError)
                .refreshable {
                    await model?.load()
                }
            }
        }
    }
}
