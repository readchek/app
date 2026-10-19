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
                .buttonStyle(.glassProminent)
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
                    .buttonStyle(.glass)
                }
            case .loaded(let content):
                let statuses = ReadingStatuses(states)
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        if !content.continueReading.isEmpty {
                            PublicationShelf(title: "Continue Reading", publications: content.continueReading, statuses: statuses, large: true)
                        }
                        if !content.recentlyAdded.isEmpty {
                            PublicationShelf(title: "Recently Added", publications: content.recentlyAdded, statuses: statuses, large: false)
                        }
                        LibraryLinks(account: account.id, libraries: content.libraries)
                    }
                    .padding(.vertical)
                }
                .refreshable {
                    await model?.load()
                }
            }
        }
    }
}

/// A row of covers you can swipe through.
struct PublicationShelf: View {
    let title: LocalizedStringKey
    let publications: [RemotePublication]
    let statuses: ReadingStatuses
    let large: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: large ? 20 : 16) {
                    ForEach(publications) { publication in
                        RemotePublicationTile(publication: publication, status: statuses[publication.id], width: tileWidth)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }

    private var tileWidth: CGFloat {
        switch (large, sizeClass == .regular) {
        case (true, true): 190
        case (true, false): 150
        case (false, true): 130
        case (false, false): 108
        }
    }
}

private struct LibraryLinks: View {
    let account: UUID
    let libraries: [ChekAPI.Library]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Libraries")
            VStack(spacing: 0) {
                ForEach(libraries) { library in
                    NavigationLink(value: Route.serverLibrary(account, library)) {
                        HStack {
                            Label(library.name, systemImage: "books.vertical")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.forward")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if library.id != libraries.last?.id {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
            .background(.background.secondary, in: .rect(cornerRadius: 22))
            .padding(.horizontal)
        }
    }
}
