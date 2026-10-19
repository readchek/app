import SwiftUI

/// A book in the library grid: its cover, title and where you are in it.
struct BookGridItem: View {
    let book: Book
    @Binding var bookToRemove: Book?
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            router.open(ReadingItem(book))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                CoverView(source: book.coverURL.map(CoverSource.file) ?? .none, title: book.title)
                    .readerTransitionSource(book.ref)
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack {
                        ReadingStatusLabel(status: book.readingStatus)
                        Spacer(minLength: 0)
                        Text(book.formatName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            BookActions(book: book, bookToRemove: $bookToRemove)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the book"))
    }
}

/// A book in the library list.
struct BookRow: View {
    let book: Book
    @Binding var bookToRemove: Book?
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            router.open(ReadingItem(book))
        } label: {
            HStack(spacing: 14) {
                CoverView(source: book.coverURL.map(CoverSource.file) ?? .none, title: book.title, cornerRadius: 4)
                    .frame(width: 48)
                    .readerTransitionSource(book.ref)
                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                    if !book.authors.isEmpty {
                        Text(book.authors)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        ReadingStatusLabel(status: book.readingStatus)
                        Text(book.formatName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            BookActions(book: book, bookToRemove: $bookToRemove)
        }
        .swipeActions {
            Button("Remove", systemImage: "trash", role: .destructive) {
                bookToRemove = book
            }
        }
    }
}

/// What you can do with a book from its context menu.
struct BookActions: View {
    let book: Book
    @Binding var bookToRemove: Book?
    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var library

    var body: some View {
        Button("Read", systemImage: "book") {
            router.open(ReadingItem(book))
        }
        if book.finishedAt == nil {
            Button("Mark as Finished", systemImage: "checkmark.circle") {
                library.markFinished(book)
            }
        } else {
            Button("Mark as Unread", systemImage: "arrow.counterclockwise") {
                library.markUnread(book)
            }
        }
        ShareLink(item: book.fileURL) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        Divider()
        Button("Remove…", systemImage: "trash", role: .destructive) {
            bookToRemove = book
        }
    }
}

extension View {
    /// Asks before removing a book, since its file goes with it.
    func removeBookConfirmation(book: Binding<Book?>) -> some View {
        modifier(RemoveBookConfirmation(book: book))
    }
}

private struct RemoveBookConfirmation: ViewModifier {
    @Binding var book: Book?
    @Environment(LibraryStore.self) private var library

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Remove This Book?",
            isPresented: Binding { book != nil } set: { if !$0 { book = nil } },
            titleVisibility: .visible,
            presenting: book
        ) { book in
            Button("Remove “\(book.title)”", role: .destructive) {
                library.remove(book)
            }
        } message: { _ in
            Text("Its file and your place in it are deleted from this device.")
        }
    }
}
