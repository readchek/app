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
                .demoBanner()
                .navigationTitle("Reading Now")
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
    @Query(filter: #Predicate<SourceReadingState> { $0.lastOpenedAt != nil }, sort: \SourceReadingState.lastOpenedAt, order: .reverse)
    private var sourceStates: [SourceReadingState]
    @Query(sort: \ServerAccount.sortIndex) private var accounts: [ServerAccount]
    @Query private var follows: [FollowedSeries]
    @Environment(ServerStore.self) private var servers
    @Environment(ServerSync.self) private var sync
    @Environment(FollowStore.self) private var followStore
    @State private var model = HomeServersModel()

    var body: some View {
        let continueReading = continueReadingItems()
        let signedOut = accounts.filter { servers.state(of: $0.id) == .signedOut }
        let hasShelves = !continueReading.isEmpty || !newBooks.isEmpty || !model.newOnServers.isEmpty || !model.sites.isEmpty || !follows.isEmpty
        Group {
            if !hasShelves, accounts.isEmpty {
                HomeStartView()
            } else if !hasShelves, !signedOut.isEmpty {
                // Everything here came from servers you're signed out of, so
                // the way back in is the one thing worth showing.
                SignedOutHomeView(accounts: signedOut)
            } else {
                // A plain list of shelves, the same page as a shared
                // library's own screen.
                List {
                    if !continueReading.isEmpty {
                        Shelf(title: "Continue Reading", items: continueReading, isFeatured: true)
                            .shelfRow()
                    }
                    FollowingShelf()
                    if !newBooks.isEmpty {
                        Shelf(title: "Recently Added", items: newBooks.prefix(20).map(PublicationItem.init))
                            .shelfRow()
                    }
                    // A shelf per shared library, headed by its name and
                    // leading to its screen, as each site's shelf does.
                    ForEach(model.newOnServers) { shelf in
                        Shelf(title: "\(shelf.serverName)", items: shelf.publications.map { publication in
                            PublicationItem(publication, status: statuses[publication.ref] ?? .new, cover: servers.cover(of: publication.id, on: publication.server))
                        }, route: .server(shelf.id))
                        .shelfRow()
                    }
                    // What each site you've added shows first, so adding
                    // one puts something to read here straight away.
                    ForEach(model.sites) { shelf in
                        SiteShelf(shelf: shelf)
                            .shelfRow()
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    async let sites: Void = model.loadSites(from: servers)
                    await model.load(from: servers)
                    await sites
                    await followStore.checkForNewChapters(force: true)
                }
            }
        }
        .task(id: servers.signedOut) {
            // Sites answer slowly, so their shelves load beside the rest
            // rather than holding it up.
            async let sites: Void = model.loadSites(from: servers)
            await model.load(from: servers)
            await sites
            await sync.fillMissingSourceCovers()
            await followStore.checkForNewChapters()
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
        // One entry per series, its latest chapter: the next chapter is a
        // tap away in the series, and a shelf of one series' chapters
        // would crowd out everything else.
        var seriesShown = Set<String>()
        for state in sourceStates {
            let series = "\(state.serverID)/\(state.sourceID)/\(state.seriesID)"
            guard seriesShown.insert(series).inserted, state.readingStatus != .finished else { continue }
            let cover = servers.sourceImage(state.seriesCoverPath, on: state.serverID)
            dated.append((PublicationItem(state, cover: cover), state.lastOpenedAt ?? .distantPast))
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

    /// The series a site added to a shared library shows first.
    struct SiteShelf: Identifiable, Codable {
        let account: UUID
        let source: ChekAPI.InstalledExtension
        let series: [ChekAPI.SourceSeriesItem]

        var id: String { "\(account.uuidString)/\(source.id)" }
    }

    private(set) var elsewhere: [Elsewhere] = []
    private(set) var newOnServers: [ServerShelf] = []
    private(set) var sites: [SiteShelf] = []
    private var hasShownSnapshot = false
    private var hasShownSitesSnapshot = false

    func load(from servers: ServerStore) async {
        let signedIn = servers.accounts().filter { servers.state(of: $0.id) == .signedIn }
        // What the servers said last time shows at once, and stands in
        // when they can't be reached, rather than empty shelves until
        // every server has answered.
        if !hasShownSnapshot {
            hasShownSnapshot = true
            if let snapshot = await HomeSnapshot.read() {
                let names = Dictionary(signedIn.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
                elsewhere = snapshot.elsewhere
                    .filter { names[$0.publication.server] != nil }
                    .map { Elsewhere(publication: $0.publication, status: ReadingStatus(progress: $0.progress, finished: false, opened: true), date: $0.date) }
                newOnServers = snapshot.shelves.compactMap { shelf in
                    names[shelf.id].map { ServerShelf(id: shelf.id, serverName: $0, publications: shelf.publications) }
                }
            }
        }
        var elsewhere: [Elsewhere] = []
        var snapshotElsewhere: [HomeSnapshot.Elsewhere] = []
        var shelves: [ServerShelf] = []
        var reached: Set<UUID> = []
        for account in signedIn {
            let id = account.id
            // The shared demo account's places aren't yours.
            if id != DemoMode.accountID, let reading = try? await servers.request(id, { client throws(ChekError) in try await client.continueReading() }) {
                reached.insert(id)
                for item in reading {
                    let progress = item.progress.locator?.locations.totalProgression
                    let publication = RemotePublication(item.publication, server: id)
                    let date = item.progress.updatedAt ?? .distantPast
                    elsewhere.append(Elsewhere(
                        publication: publication,
                        status: ReadingStatus(progress: progress, finished: false, opened: true),
                        date: date
                    ))
                    snapshotElsewhere.append(HomeSnapshot.Elsewhere(publication: publication, progress: progress, date: date))
                }
            }
            if let recent = try? await servers.request(id, { client throws(ChekError) in try await client.recentlyAdded(cursor: nil) }) {
                reached.insert(id)
                if !recent.items.isEmpty {
                    shelves.append(ServerShelf(id: id, serverName: account.name, publications: recent.items.prefix(20).map { RemotePublication($0, server: id) }))
                }
            }
        }
        // A server that didn't answer keeps what it showed before.
        for shelf in newOnServers where !reached.contains(shelf.id) && signedIn.contains(where: { $0.id == shelf.id }) {
            shelves.append(shelf)
        }
        for item in self.elsewhere where !reached.contains(item.publication.server) && signedIn.contains(where: { $0.id == item.publication.server }) {
            elsewhere.append(item)
            snapshotElsewhere.append(HomeSnapshot.Elsewhere(publication: item.publication, progress: item.status.progress, date: item.date))
        }
        self.elsewhere = elsewhere
        newOnServers = shelves
        await HomeSnapshot(
            elsewhere: snapshotElsewhere,
            shelves: shelves.map { HomeSnapshot.Shelf(id: $0.id, serverName: $0.serverName, publications: $0.publications) }
        ).write()
    }

    /// Fills a shelf for every site added to a signed-in library, from the
    /// first page each one lists.
    func loadSites(from servers: ServerStore) async {
        let signedIn = servers.accounts().filter { servers.state(of: $0.id) == .signedIn }
        let accounts = Set(signedIn.map(\.id))
        if !hasShownSitesSnapshot {
            hasShownSitesSnapshot = true
            if let saved = await SiteShelfSnapshot.read() {
                sites = saved.filter { accounts.contains($0.account) }
            }
        }
        var shelves: [SiteShelf] = []
        for account in signedIn {
            let id = account.id
            guard let installed = try? await servers.request(id, { client throws(ChekError) in try await client.installedExtensionsIfSupported() }) else {
                // Not reached: what it showed before stays.
                shelves += sites.filter { $0.account == id }
                continue
            }
            for source in installed ?? [] where source.usable {
                if let page = try? await servers.request(id, { client throws(ChekError) in try await client.search(source: source.id, query: "", page: 1) }) {
                    if !page.items.isEmpty {
                        shelves.append(SiteShelf(account: id, source: source, series: Array(page.items.prefix(20))))
                    }
                } else if let before = sites.first(where: { $0.account == id && $0.source.id == source.id }) {
                    // A site that's slow or down today keeps yesterday's shelf.
                    shelves.append(before)
                }
            }
        }
        sites = shelves
        await SiteShelfSnapshot.write(shelves)
    }
}

/// The site shelves Home last showed, kept between launches so they appear
/// at once rather than after every site has answered.
nonisolated private enum SiteShelfSnapshot {
    private static let url = URL.cachesDirectory.appending(path: "home-sites.json")

    @concurrent
    static func read() async -> [HomeServersModel.SiteShelf]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([HomeServersModel.SiteShelf].self, from: data)
    }

    @concurrent
    static func write(_ shelves: [HomeServersModel.SiteShelf]) async {
        guard let data = try? JSONEncoder().encode(shelves) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// A site's shelf: its name leading to everything it has, then the series
/// it shows first.
private struct SiteShelf: View {
    let shelf: HomeServersModel.SiteShelf

    var body: some View {
        CoverShelf(title: "\(shelf.source.name)", route: .source(shelf.account, shelf.source)) {
            ForEach(shelf.series) { series in
                SourceSeriesCell(account: shelf.account, source: shelf.source.id, series: series)
                    .shelfCell()
            }
        }
    }
}

/// What Home last showed from servers, kept between launches.
nonisolated private struct HomeSnapshot: Codable {
    struct Elsewhere: Codable {
        var publication: RemotePublication
        var progress: Double?
        var date: Date
    }

    struct Shelf: Codable {
        var id: UUID
        var serverName: String
        var publications: [RemotePublication]
    }

    var elsewhere: [Elsewhere]
    var shelves: [Shelf]

    /// In Caches: it's remade from the servers on every launch that
    /// reaches them, so losing it costs nothing.
    private static let url = URL.cachesDirectory.appending(path: "home-servers.json")

    @concurrent
    static func read() async -> HomeSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(HomeSnapshot.self, from: data)
    }

    @concurrent
    func write() async {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.url, options: .atomic)
    }
}

/// Reading Now when every shared library needs signing in again and
/// nothing else is here.
private struct SignedOutHomeView: View {
    let accounts: [ServerAccount]
    @Environment(AppRouter.self) private var router

    var body: some View {
        EmptyState(
            "Signed Out",
            systemImage: "person.crop.circle.badge.exclamationmark",
            description: Text(accounts.count == 1
                ? "Sign in to \(accounts[0].name) to keep reading."
                : "Sign in to your shared libraries to keep reading.")
        ) {
            ForEach(accounts.prefix(1)) { account in
                Button(accounts.count == 1 ? String(localized: "Sign In") : String(localized: "Sign In to \(account.name)")) {
                    router.sheet = .signIn(account.id)
                }
            }
        } secondary: {
            ForEach(accounts.dropFirst()) { account in
                Button("Sign In to \(account.name)") {
                    router.sheet = .signIn(account.id)
                }
            }
            Button("Add Books") {
                router.addBooks()
            }
        }
    }
}
