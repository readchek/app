import ChekReader
import Foundation
import SwiftData

extension ChekSchemaV2 {
    /// Your place in a chapter read straight from a source, without the
    /// server keeping it as a library.
    ///
    /// Sources have no saved positions on the server, so this is the only
    /// copy, kept on the device. ``ProgressStore`` writes it on every page.
    @Model
    final class SourceReadingState {
        /// ``PublicationRef/storageKey`` of the chapter.
        @Attribute(.unique) var key: String
        var serverID: UUID
        /// The extension's id, such as `page.chek.mangadex`.
        var sourceID: String
        var seriesID: String
        var seriesTitle: String
        var chapterID: String
        var chapterTitle: String
        /// The position as Readium-compatible Locator JSON.
        var location: Data?
        var progress: Double?
        var lastOpenedAt: Date?

        init(serverID: UUID, sourceID: String, seriesID: String, seriesTitle: String, chapterID: String, chapterTitle: String) {
            key = PublicationRef.source(serverID, sourceID, chapterID).storageKey
            self.serverID = serverID
            self.sourceID = sourceID
            self.seriesID = seriesID
            self.seriesTitle = seriesTitle
            self.chapterID = chapterID
            self.chapterTitle = chapterTitle
        }

        var savedLocation: Locator? {
            location.flatMap { try? JSONDecoder().decode(Locator.self, from: $0) }
        }

        var readingStatus: ReadingStatus {
            ReadingStatus(progress: progress, finished: (progress ?? 0) >= ReadingStatus.finishedThreshold, opened: lastOpenedAt != nil)
        }
    }
}
