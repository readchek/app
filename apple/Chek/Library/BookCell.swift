import SwiftUI

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
            Button("Mark as Unread", systemImage: "circle") {
                library.markUnread(book)
            }
        }
        ShareLink(item: book.fileURL) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        Divider()
        Button("Delete…", systemImage: "trash", role: .destructive) {
            bookToRemove = book
        }
    }
}

extension View {
    /// Asks before deleting a book, since its file goes with it.
    func removeBookConfirmation(book: Binding<Book?>) -> some View {
        modifier(RemoveBookConfirmation(book: book))
    }
}

private struct RemoveBookConfirmation: ViewModifier {
    @Binding var book: Book?
    @Environment(LibraryStore.self) private var library

    func body(content: Content) -> some View {
        content.confirmationDialog(
            Text("Delete “\(book?.title ?? "")”?"),
            isPresented: Binding { book != nil } set: { if !$0 { book = nil } },
            titleVisibility: .visible,
            presenting: book
        ) { book in
            Button("Delete Book", role: .destructive) {
                library.remove(book)
            }
        } message: { _ in
            Text("Its file and reading position are deleted from this device.")
        }
    }
}
