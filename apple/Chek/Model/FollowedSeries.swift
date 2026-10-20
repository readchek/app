import Foundation
import SwiftData

extension ChekSchemaV4 {
    /// A series from a server's source you're following, so new chapters
    /// show up on Reading Now without searching for it again.
    @Model
    final class FollowedSeries {
        /// `server/source/series`, one follow per series.
        @Attribute(.unique) var key: String
        var serverID: UUID
        var sourceID: String
        var seriesID: String
        var title: String
        var coverPath: String?
        var isRightToLeft: Bool
        var followedAt: Date
        /// How many chapters the source listed when last checked.
        var chapterCount: Int
        /// Chapters listed since you last opened the series, by the source's
        /// chapter ids, so "new" means new to you.
        var unseenChapterIDs: [String]
        var lastCheckedAt: Date?

        init(serverID: UUID, sourceID: String, seriesID: String, title: String, coverPath: String?, isRightToLeft: Bool, chapterCount: Int) {
            key = Self.key(server: serverID, source: sourceID, series: seriesID)
            self.serverID = serverID
            self.sourceID = sourceID
            self.seriesID = seriesID
            self.title = title
            self.coverPath = coverPath
            self.isRightToLeft = isRightToLeft
            self.chapterCount = chapterCount
            followedAt = .now
            unseenChapterIDs = []
        }

        static func key(server: UUID, source: String, series: String) -> String {
            "\(server.uuidString)/\(source)/\(series)"
        }
    }
}
