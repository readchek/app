import ChekReader
import Foundation
import SwiftData

extension ChekSchemaV3 {
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
        /// The series' cover as a path on the server, for showing the
        /// chapter in Continue Reading.
        var seriesCoverPath: String?
        /// Whether the series reads right to left, kept for opening it from
        /// Continue Reading.
        var isRightToLeft = false
        /// The position as Readium-compatible Locator JSON.
        var location: Data?
        var progress: Double?
        var lastOpenedAt: Date?

        init(serverID: UUID, sourceID: String, seriesID: String, seriesTitle: String, chapterID: String, chapterTitle: String, seriesCoverPath: String?, isRightToLeft: Bool) {
            key = PublicationRef.source(serverID, sourceID, chapterID).storageKey
            self.serverID = serverID
            self.sourceID = sourceID
            self.seriesID = seriesID
            self.seriesTitle = seriesTitle
            self.chapterID = chapterID
            self.chapterTitle = chapterTitle
            self.seriesCoverPath = seriesCoverPath
            self.isRightToLeft = isRightToLeft
        }

        var ref: PublicationRef {
            .source(serverID, sourceID, chapterID)
        }

        var savedLocation: Locator? {
            location.flatMap { try? JSONDecoder().decode(Locator.self, from: $0) }
        }

        var readingStatus: ReadingStatus {
            ReadingStatus(progress: progress, finished: (progress ?? 0) >= ReadingStatus.finishedThreshold, opened: lastOpenedAt != nil)
        }
    }
}

extension ChekSchemaV2 {
    /// ``ChekSchemaV3/SourceReadingState`` as V2 stored it, before it kept
    /// the series' cover. Frozen, so stores at V2 still open to migrate.
    @Model
    final class SourceReadingState {
        @Attribute(.unique) var key: String
        var serverID: UUID
        var sourceID: String
        var seriesID: String
        var seriesTitle: String
        var chapterID: String
        var chapterTitle: String
        var location: Data?
        var progress: Double?
        var lastOpenedAt: Date?

        init(key: String, serverID: UUID, sourceID: String, seriesID: String, seriesTitle: String, chapterID: String, chapterTitle: String) {
            self.key = key
            self.serverID = serverID
            self.sourceID = sourceID
            self.seriesID = seriesID
            self.seriesTitle = seriesTitle
            self.chapterID = chapterID
            self.chapterTitle = chapterTitle
        }
    }
}
