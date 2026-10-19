import ChekReader
import Foundation
import SwiftData

extension ChekSchemaV1 {
    /// Your place in a publication on a server.
    ///
    /// The device copy is what Chek shows, so Continue Reading works offline
    /// and a page turn never waits on the network. ``ProgressStore`` writes
    /// it on every page turn and uploads it when ``needsUpload`` is set.
    @Model
    final class RemoteReadingState {
        /// ``PublicationRef/storageKey`` of the publication.
        @Attribute(.unique) var key: String
        var serverID: UUID
        var publicationID: Int64
        var title: String
        var seriesID: Int64?
        var seriesTitle: String?
        var numberLabel: String?
        /// The server's format name, such as `epub` or `cbz`.
        var format: String
        var hasCover: Bool
        /// The position as Readium-compatible Locator JSON.
        var location: Data?
        var progress: Double?
        /// The server's revision of the position this copy is based on, 0
        /// when the server has none.
        var revision: Int64
        /// Whether the position changed here since it was last uploaded.
        var needsUpload: Bool
        var updatedAt: Date
        var lastOpenedAt: Date?

        init(
            serverID: UUID,
            publicationID: Int64,
            title: String,
            seriesID: Int64?,
            seriesTitle: String?,
            numberLabel: String?,
            format: String,
            hasCover: Bool,
            at date: Date = .now
        ) {
            key = PublicationRef.server(serverID, publicationID).storageKey
            self.serverID = serverID
            self.publicationID = publicationID
            self.title = title
            self.seriesID = seriesID
            self.seriesTitle = seriesTitle
            self.numberLabel = numberLabel
            self.format = format
            self.hasCover = hasCover
            revision = 0
            needsUpload = false
            updatedAt = date
        }

        var ref: PublicationRef {
            .server(serverID, publicationID)
        }

        var kind: PublicationKind {
            PublicationKind(serverFormat: format)
        }

        var savedLocation: Locator? {
            location.flatMap { try? JSONDecoder().decode(Locator.self, from: $0) }
        }

        var readingStatus: ReadingStatus {
            ReadingStatus(progress: progress, finished: (progress ?? 0) >= ReadingStatus.finishedThreshold, opened: lastOpenedAt != nil)
        }
    }
}
