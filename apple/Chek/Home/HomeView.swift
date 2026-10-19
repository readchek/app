import SwiftData
import SwiftUI

/// What you're reading first, then what's new, from the device and every
/// server.
struct HomeView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.homePath) {
            HomeContent()
                .navigationTitle("Home")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Settings", systemImage: "gearshape") {
                            router.sheet = .settings
                        }
                    }
                }
                .routeDestinations()
        }
    }
}

private struct HomeContent: View {
    @Query(filter: #Predicate<Book> { $0.lastOpenedAt != nil && $0.finishedAt == nil }, sort: \Book.recentAt, order: .reverse)
    private var startedBooks: [Book]
    @Query(filter: #Predicate<Book> { $0.lastOpenedAt == nil }, sort: \Book.addedAt, order: .reverse)
    private var newBooks: [Book]
    @Query(filter: #Predicate<RemoteReadingState> { $0.lastOpenedAt != nil }, sort: \RemoteReadingState.updatedAt, order: .reverse)
    private var remoteStates: [RemoteReadingState]
    @Query(sort: \ServerAccount.sortIndex) private var accounts: [ServerAccount]
    @Environment(ServerStore.self) private var servers
    @State private var model = HomeServersModel()

    var body: some View {
        let continueReading = continueReadingItems()
        let isEmpty = continueReading.isEmpty && newBooks.isEmpty && accounts.isEmpty
        Group {
            if isEmpty {
                HomeEmptyView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                        if let current = continueReading.first {
                            CurrentReadingHeader(item: current)
                        }
                        if continueReading.count > 1 {
                            Shelf(title: "Continue Reading", items: Array(continueReading.dropFirst()))
                        }
                        if !newBooks.isEmpty {
                            Shelf(title: "Recently Added", items: newBooks.prefix(20).map(PublicationItem.init))
                        }
                        ForEach(model.newOnServers) { shelf in
                            Shelf(title: "New on \(shelf.serverName)", items: shelf.publications.map { publication in
                                PublicationItem(publication, status: statuses[publication.ref] ?? .new, cover: servers.cover(of: publication.id, on: publication.server))
                            })
                        }
                    }
                    .padding(.vertical, 8)
                }
                .refreshable {
                    await model.load(from: servers)
                }
            }
        }
        .task(id: servers.signedOut) {
            await model.load(from: servers)
        }
    }

    private var statuses: [PublicationRef: ReadingStatus] {
        Dictionary(remoteStates.map { ($0.ref, $0.readingStatus) }, uniquingKeysWith: { first, _ in first })
    }

    /// Books here and server publications by when you last read them.
    /// Publications started on other devices follow those read here.
    private func continueReadingItems() -> [PublicationItem] {
        var dated: [(PublicationItem, Date)] = startedBooks.map { (PublicationItem($0), $0.recentAt) }
        var seen = Set<PublicationRef>()
        for state in remoteStates where state.readingStatus != .finished {
            seen.insert(state.ref)
            let publication = RemotePublication(state)
            let cover = servers.cover(of: publication.id, on: publication.server)
            dated.append((PublicationItem(publication, status: state.readingStatus, cover: cover), state.lastOpenedAt ?? state.updatedAt))
        }
        for elsewhere in model.elsewhere where !seen.contains(elsewhere.publication.ref) {
            let publication = elsewhere.publication
            let cover = servers.cover(of: publication.id, on: publication.server)
            dated.append((PublicationItem(publication, status: elsewhere.status, cover: cover), elsewhere.date))
        }
        return dated.sorted { $0.1 > $1.1 }.prefix(20).map(\.0)
    }
}

/// What Home shows from servers: what you're reading on other devices,
/// and what's new on each one.
@MainActor
@Observable
final class HomeServersModel {
    struct Elsewhere {
        let publication: RemotePublication
        let status: ReadingStatus
        let date: Date
    }

    struct ServerShelf: Identifiable {
        let id: UUID
        let serverName: String
        let publications: [RemotePublication]
    }

    private(set) var elsewhere: [Elsewhere] = []
    private(set) var newOnServers: [ServerShelf] = []

    func load(from servers: ServerStore) async {
        var elsewhere: [Elsewhere] = []
        var shelves: [ServerShelf] = []
        for account in servers.accounts() where servers.state(of: account.id) == .signedIn {
            let id = account.id
            if let reading = try? await servers.request(id, { client throws(ChekError) in try await client.continueReading() }) {
                for item in reading {
                    let progress = item.progress.locator?.locations.totalProgression
                    elsewhere.append(Elsewhere(
                        publication: RemotePublication(item.publication, server: id),
                        status: ReadingStatus(progress: progress, finished: false, opened: true),
                        date: item.progress.updatedAt ?? .distantPast
                    ))
                }
            }
            if let recent = try? await servers.request(id, { client throws(ChekError) in try await client.recentlyAdded(cursor: nil) }), !recent.items.isEmpty {
                shelves.append(ServerShelf(id: id, serverName: account.name, publications: recent.items.prefix(20).map { RemotePublication($0, server: id) }))
            }
        }
        self.elsewhere = elsewhere
        newOnServers = shelves
    }
}

/// Shown before there's anything to read, with the two ways to start.
private struct HomeEmptyView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ContentUnavailableView {
            Label("Nothing to Read Yet", systemImage: "books.vertical")
        } description: {
            Text("Add books and comics from Files, or connect a Chek server to read from it.")
        } actions: {
            Button("Add Books") {
                router.addBooks()
            }
            .buttonStyle(.borderedProminent)
            Button("Connect a Server") {
                router.sheet = .addServer
            }
        }
    }
}

/// The publication you're reading now, large, with one button to go on.
private struct CurrentReadingHeader: View {
    let item: PublicationItem
    @Environment(AppRouter.self) private var router
    @Environment(ServerSync.self) private var sync

    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            OpenPublicationButton(item: item) {
                CoverView(source: item.cover, title: item.title, cornerRadius: 6)
                    .frame(width: 132)
                    .readerTransitionSource(item.id)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Reading Now")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(item.title)
                    .font(.title2.weight(.bold))
                    .lineLimit(3)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let progress = item.status.progress, progress >= 0.01 {
                    Text("\(progress, format: .percent.precision(.fractionLength(0))) read")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Button("Continue", systemImage: "play.fill", action: resume)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.margin)
    }

    private func resume() {
        switch item.source {
        case .local(let book): router.open(ReadingItem(book))
        case .remote(let publication): router.open(publication, using: sync)
        }
    }
}
