import ChekReader
import SwiftUI

/// Reads one book, starting where it was left and saving the position as
/// the reader moves.
struct ReaderScreen: View {
    let book: Book
    @State private var controller = ReaderController()

    var body: some View {
        ZStack {
            NavigatorView(controller: controller)
                .ignoresSafeArea(edges: .bottom)
            ReaderStatus(state: controller.state) {
                Task { await open() }
            }
        }
        .background {
            LocationSaver(controller: controller, book: book)
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .task(id: book.id) {
            await open()
        }
    }

    private func open() async {
        book.lastOpenedAt = .now
        book.recentAt = .now
        // Failures show through the controller's state.
        try? await controller.open(.file(book.fileURL), at: book.savedLocation)
    }
}

/// Saves the location as it changes. It reads `location` on its own so a
/// page turn redraws only this view.
private struct LocationSaver: View {
    let controller: ReaderController
    let book: Book

    var body: some View {
        Color.clear
            .onChange(of: controller.location) { _, location in
                if let location {
                    book.savedLocation = location
                }
            }
    }
}

/// Loading and failure states drawn over the reader.
private struct ReaderStatus: View {
    let state: ReaderController.State
    let retry: () -> Void

    var body: some View {
        switch state {
        case .idle, .opening, .closing:
            ProgressView()
        case .failed(let error):
            ContentUnavailableView {
                Label {
                    Text(verbatim: error.localizedDescription)
                } icon: {
                    Image(systemName: "book.closed")
                }
            } description: {
                if let suggestion = error.recoverySuggestion {
                    Text(verbatim: suggestion)
                }
            } actions: {
                Button("Try Again", action: retry)
            }
        case .ready, .closed:
            EmptyView()
        }
    }
}
