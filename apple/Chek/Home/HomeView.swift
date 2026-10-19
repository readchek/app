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

/// Books you've started and not finished, most recent first, as big
/// covers you can swipe through.
private struct ContinueReadingSection: View {
    @Query(
        filter: #Predicate<Book> { $0.lastOpenedAt != nil && $0.finishedAt == nil },
        sort: \Book.recentAt,
        order: .reverse
    )
    private var books: [Book]

    var body: some View {
        if !books.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Continue Reading")
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .bottom, spacing: 20) {
                        ForEach(books.prefix(20)) { book in
                            ContinueReadingCard(book: book)
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

private struct ContinueReadingCard: View {
    let book: Book
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Button {
            router.open(ReadingItem(book))
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                CoverView(source: book.coverURL.map(CoverSource.file) ?? .none, title: book.title, cornerRadius: 8)
                    .readerTransitionSource(book.ref)
                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let progress = book.readingStatus.progress {
                        HStack(spacing: 8) {
                            ReadingProgressBar(progress: progress)
                            Text(progress, format: .percent.precision(.fractionLength(0)))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
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
