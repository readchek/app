import SwiftData
import SwiftUI

/// What's on one server: where you are in it on any device, what's new,
/// and its libraries.
struct ServerHomeView: View {
    let account: UUID
    @Environment(ServerStore.self) private var servers
    @State private var model: ServerHomeModel?

    var body: some View {
        Group {
            if let server = servers.account(account) {
                ServerHomeContent(account: server, model: model)
                    .navigationTitle(server.name)
            } else {
                ContentUnavailableView("Server Removed", systemImage: "server.rack")
            }
        }
        .task(id: account) {
            let model = model ?? ServerHomeModel(account: account, servers: servers)
            self.model = model
            await model.load()
        }
    }
}

/// Loads a server's home in one go, so the sections appear together.
@MainActor
@Observable
final class ServerHomeModel {
    struct Content: Equatable {
        var continueReading: [RemotePublication]
        var recentlyAdded: [RemotePublication]
        var libraries: [ChekAPI.Library]
    }

    private(set) var state: LoadState<Content> = .idle
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
                // The three load side by side. `async let` loses the error
                // type, so it's restored for the store to see sign-outs.
                do {
                    async let libraries = client.libraries()
                    async let recent = client.recentlyAdded(cursor: nil)
                    async let reading = client.continueReading()
                    return try await Content(
                        continueReading: reading.map { RemotePublication($0.publication, server: account) },
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
        } catch {
            if state.value == nil {
                state = .failed(DisplayError(error))
            }
        }
    }
}

private struct ServerHomeContent: View {
    let account: ServerAccount
    let model: ServerHomeModel?
    @Environment(ServerStore.self) private var servers
    @Environment(AppRouter.self) private var router
    @Query private var states: [RemoteReadingState]

    init(account: ServerAccount, model: ServerHomeModel?) {
        self.account = account
        self.model = model
        _states = Query(filter: RemoteReadingState.onServer(account.id))
    }

    var body: some View {
        if servers.state(of: account.id) == .signedOut {
            ContentUnavailableView {
                Label("Signed Out", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text("Sign in to \(account.name) again to read from it.")
            } actions: {
                Button("Sign In") {
                    router.sheet = .signIn(account.id)
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            switch model?.state ?? .idle {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.large)
            case .failed(let error):
                ContentUnavailableView {
                    Label(error.title, systemImage: "wifi.exclamationmark")
                } description: {
                    if let message = error.message {
                        Text(message)
                    }
                } actions: {
                    Button("Try Again") {
                        Task { await model?.load() }
                    }
                    .buttonStyle(.bordered)
                }
            case .loaded(let content):
                let statuses = ReadingStatuses(states)
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                        if !content.continueReading.isEmpty {
                            Shelf(
                                title: "Continue Reading",
                                items: content.continueReading.map { servers.item($0, status: statuses[$0.id]) },
                                isFeatured: true
                            )
                        }
                        if !content.recentlyAdded.isEmpty {
                            Shelf(title: "Recently Added", items: content.recentlyAdded.map { servers.item($0, status: statuses[$0.id]) })
                        }
                        if !content.libraries.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                SectionHeader(title: "Libraries")
                                ForEach(content.libraries) { library in
                                    NavigationRow(
                                        title: library.name,
                                        systemImage: "books.vertical",
                                        value: Route.serverLibrary(account.id, library),
                                        showsDivider: library.id != content.libraries.last?.id
                                    )
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .refreshable {
                    await model?.load()
                }
            }
        }
    }
}
