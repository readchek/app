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
        case .source:
            guard let state = sourceState(ref) else { return }
            state.lastOpenedAt = now
        }
        save()
    }

    /// Records `locator` as the place in `ref`. `isAtEnd` says it's the
    /// last page, which finishes it: a position's progress is where its
    /// page starts, so a comic's last page reports 19 of 20 as 95%, and
    /// without this a chapter read to the end would never count as read.
    func record(_ locator: Locator, in ref: PublicationRef, isAtEnd: Bool = false) {
        guard let data = try? JSONEncoder().encode(locator) else { return }
        let progress = isAtEnd ? 1 : locator.locations.totalProgression
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
        case .source:
            guard let state = sourceState(ref), state.location != data else { return }
            state.location = data
            if let progress {
                state.progress = progress
            }
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

    func sourceState(_ ref: PublicationRef) -> SourceReadingState? {
        let key = ref.storageKey
        var descriptor = FetchDescriptor<SourceReadingState>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Brings your places in a source series' chapters up to date with
    /// what the source now says about it, such as a new cover or title.
    func updateSourceSeries(_ series: ChekAPI.SourceSeries, server: UUID, source: String) {
        let seriesID = series.id
        let descriptor = FetchDescriptor<SourceReadingState>(predicate: #Predicate {
            $0.serverID == server && $0.sourceID == source && $0.seriesID == seriesID
        })
        let rightToLeft = series.readingDirection == "rtl"
        var changed = false
        for state in (try? context.fetch(descriptor)) ?? [] {
            if state.seriesCoverPath != series.coverUrl {
                state.seriesCoverPath = series.coverUrl
                changed = true
            }
            if state.seriesTitle != series.title {
                state.seriesTitle = series.title
                changed = true
            }
            if state.isRightToLeft != rightToLeft {
                state.isRightToLeft = rightToLeft
                changed = true
            }
        }
        if changed {
            save()
        }
    }

    /// Marks source chapters read without opening them, as when you've
    /// read them elsewhere.
    func markRead(_ chapters: [SourceChapterRef]) {
        for chapter in chapters {
            let state = sourceState(for: chapter)
            state.progress = 1
            state.lastOpenedAt = state.lastOpenedAt ?? .now
        }
        save()
    }

    func markRead(_ chapter: SourceChapterRef) {
        markRead([chapter])
    }

    /// Clears your place in a source chapter, so it reads as new.
    func markUnread(_ chapter: SourceChapterRef) {
        guard let state = sourceState(chapter.ref) else { return }
        state.progress = nil
        state.location = nil
        state.lastOpenedAt = nil
        save()
    }

    /// The device's record of a source chapter, made the first time it opens.
    func sourceState(for chapter: SourceChapterRef) -> SourceReadingState {
        if let state = sourceState(chapter.ref) {
            return state
        }
        let state = SourceReadingState(
            serverID: chapter.server,
            sourceID: chapter.source,
            seriesID: chapter.seriesID,
            seriesTitle: chapter.seriesTitle,
            chapterID: chapter.chapterID,
            chapterTitle: chapter.chapterTitle,
            seriesCoverPath: chapter.seriesCoverPath,
            isRightToLeft: chapter.isRightToLeft
        )
        context.insert(state)
        save()
        return state
    }

    private func save() {
        // SwiftData's autosave can lag by several seconds, and a position
        // lost to quitting the app is the one thing a reader mustn't do.
        try? context.save()
    }
}
