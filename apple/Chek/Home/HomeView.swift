import SwiftData
import SwiftUI

/// What you're reading, first, then what's new.
struct HomeView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    ContinueReadingSection()
                    RecentlyAddedSection()
                    WelcomeSection()
                }
                .padding(.vertical)
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings", systemImage: "gearshape") {
                        router.sheet = .settings
                    }
                }
            }
        }
    }
}

/// Everything you've started and not finished, from this device and your
/// servers, most recent first, as big covers you can swipe through.
private struct ContinueReadingSection: View {
    @Query(filter: #Predicate<Book> { $0.lastOpenedAt != nil && $0.finishedAt == nil }, sort: \Book.recentAt, order: .reverse)
    private var books: [Book]
    @Query(filter: #Predicate<RemoteReadingState> { $0.lastOpenedAt != nil }, sort: \RemoteReadingState.updatedAt, order: .reverse)
    private var remote: [RemoteReadingState]
    @Environment(ServerStore.self) private var servers
    @State private var elsewhere = ElsewhereModel()

    var body: some View {
        let entries = ContinueEntry.merge(books: books, remote: remote, elsewhere: elsewhere.items)
        Group {
            if !entries.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Continue Reading")
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 20) {
                            ForEach(entries.prefix(20)) { entry in
                                switch entry {
                                case .local(let book):
                                    ContinueReadingCard(
                                        target: .local(book),
                                        title: book.title,
                                        cover: book.coverURL.map(CoverSource.file) ?? .none,
                                        ref: book.ref,
                                        progress: book.readingStatus.progress
                                    )
                                case .remote(let publication, let status):
                                    ContinueReadingCard(
                                        target: .remote(publication),
                                        title: publication.displayTitle,
                                        cover: servers.cover(of: publication.id, on: publication.server),
                                        ref: publication.ref,
                                        progress: status.progress
                                    )
                                }
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
        }
        .task(id: servers.signedOut) {
            await elsewhere.load(from: servers)
        }
    }
}

/// One thing to continue: a book here, or a publication on a server.
private enum ContinueEntry: Identifiable {
    case local(Book)
    case remote(RemotePublication, ReadingStatus)

    var id: PublicationRef {
        switch self {
        case .local(let book): book.ref
        case .remote(let publication, _): publication.ref
        }
    }

    /// Books here and server publications by when you last read them, with
    /// publications started on other devices after the ones read here.
    static func merge(books: [Book], remote: [RemoteReadingState], elsewhere: [(RemotePublication, ReadingStatus, Date)]) -> [ContinueEntry] {
        var dated: [(ContinueEntry, Date)] = books.map { (.local($0), $0.recentAt) }
        var seen = Set<PublicationRef>()
        for state in remote where state.readingStatus != .finished {
            seen.insert(state.ref)
            dated.append((.remote(RemotePublication(state), state.readingStatus), state.lastOpenedAt ?? state.updatedAt))
        }
        for (publication, status, date) in elsewhere where !seen.contains(publication.ref) {
            dated.append((.remote(publication, status), date))
        }
        return dated.sorted { $0.1 > $1.1 }.map(\.0)
    }
}

/// Publications you're reading on other devices, from each server's
/// Continue Reading. Loaded when Home appears and kept between visits.
@MainActor
@Observable
private final class ElsewhereModel {
    private(set) var items: [(RemotePublication, ReadingStatus, Date)] = []

    func load(from servers: ServerStore) async {
        var found: [(RemotePublication, ReadingStatus, Date)] = []
        for account in servers.accounts() where servers.state(of: account.id) == .signedIn {
            let id = account.id
            guard let reading = try? await servers.request(id, { client throws(ChekError) in try await client.continueReading() }) else { continue }
            for item in reading {
                let progress = item.progress.locator?.locations.totalProgression
                let status = ReadingStatus(progress: progress, finished: false, opened: true)
                found.append((RemotePublication(item.publication, server: id), status, item.progress.updatedAt ?? .distantPast))
            }
        }
        items = found
    }
}

/// A big cover with your progress under it. Books here open straight
/// away; server publications open once their position is checked.
private struct ContinueReadingCard: View {
    enum Target {
        case local(Book)
        case remote(RemotePublication)
    }

    let target: Target
    let title: String
    let cover: CoverSource
    let ref: PublicationRef
    let progress: Double?
    @Environment(AppRouter.self) private var router
    @Environment(ServerSync.self) private var sync
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Button {
            switch target {
            case .local(let book): router.open(ReadingItem(book))
            case .remote(let publication): router.open(publication, using: sync)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                CoverView(source: cover, title: title, cornerRadius: 8)
                    .overlay {
                        if router.opening == ref {
                            ProgressView()
                                .padding(10)
                                .glassEffect(.regular, in: .circle)
                        }
                    }
                    .readerTransitionSource(ref)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        ReadingProgressBar(progress: progress ?? 0)
                        Text(progress ?? 0, format: .percent.precision(.fractionLength(0)))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: sizeClass == .regular ? 190 : 150)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}


/// Books added but not opened yet.
private struct RecentlyAddedSection: View {
    @Query(filter: #Predicate<Book> { $0.lastOpenedAt == nil }, sort: \Book.addedAt, order: .reverse)
    private var books: [Book]

    var body: some View {
        if !books.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Recently Added")
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .bottom, spacing: 16) {
                        ForEach(books.prefix(20)) { book in
                            SmallCoverButton(book: book)
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
    }
}

private struct SmallCoverButton: View {
    let book: Book
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            router.open(ReadingItem(book))
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                CoverView(source: book.coverURL.map(CoverSource.file) ?? .none, title: book.title)
                    .readerTransitionSource(book.ref)
                Text(book.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .frame(width: 104)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Shown while the library is empty, with the two ways to start.
private struct WelcomeSection: View {
    @Query private var books: [Book]
    @Environment(AppRouter.self) private var router

    init() {
        var descriptor = FetchDescriptor<Book>()
        descriptor.fetchLimit = 1
        _books = Query(descriptor)
    }

    var body: some View {
        if books.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                Text("Welcome to Chek")
                    .font(.title2.bold())
                Text("Read books and comics from the Files app, kept on this device with no account needed. Your place is saved on every page.")
                    .foregroundStyle(.secondary)
                Button {
                    router.addBooks()
                } label: {
                    Label("Add Books", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
            .padding(24)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
            .padding(.horizontal)
        }
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.title2.bold())
            .padding(.horizontal)
            .accessibilityAddTraits(.isHeader)
    }
}
