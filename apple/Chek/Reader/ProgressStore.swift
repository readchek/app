import ChekReader
import Foundation
import Observation
import SwiftData

/// Saves reading positions for every source.
///
/// Positions are written to the device on every page turn, so quitting
/// mid-book never loses your place. Server positions are then uploaded by
/// ``ServerSync``, which reads ``RemoteReadingState/needsUpload``.
@MainActor
@Observable
final class ProgressStore {
    private let context: ModelContext
    /// Bumped whenever a server position needs uploading, so the syncer can
    /// watch one value instead of every reading state.
    private(set) var pendingUploads = 0

    init(context: ModelContext) {
        self.context = context
    }

    /// Notes that `ref` was opened now, which moves it to the front of
    /// Continue Reading.
    func didOpen(_ ref: PublicationRef) {
        let now = Date.now
        switch ref {
        case .local(let id):
            guard let book = book(id) else { return }
            book.lastOpenedAt = now
            book.recentAt = now
        case .server:
            guard let state = readingState(ref) else { return }
            state.lastOpenedAt = now
        }
        save()
    }

    /// Records `locator` as the place in `ref`.
    func record(_ locator: Locator, in ref: PublicationRef) {
        guard let data = try? JSONEncoder().encode(locator) else { return }
        let progress = locator.locations.totalProgression
        switch ref {
        case .local(let id):
            guard let book = book(id), book.location != data else { return }
            book.location = data
            if let progress {
                book.progress = progress
                if progress >= ReadingStatus.finishedThreshold, book.finishedAt == nil {
                    book.finishedAt = .now
                }
            }
        case .server:
            guard let state = readingState(ref), state.location != data else { return }
            state.location = data
            if let progress {
                state.progress = progress
            }
            state.updatedAt = .now
            state.needsUpload = true
            pendingUploads += 1
        }
        save()
    }

    func book(_ id: UUID) -> Book? {
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func readingState(_ ref: PublicationRef) -> RemoteReadingState? {
        let key = ref.storageKey
        var descriptor = FetchDescriptor<RemoteReadingState>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func save() {
        // SwiftData's autosave can lag by several seconds, and a position
        // lost to quitting the app is the one thing a reader mustn't do.
        try? context.save()
    }
}
