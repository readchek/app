import Foundation

/// What a source last said about a series and the chapters seen of it,
/// kept on the device so the series still shows, and the next chapter is
/// still known, when the server can't be reached, as when reading
/// downloaded chapters offline.
nonisolated enum SeriesCache {
    /// A chapter and where it stands in the series, counting from 1 in
    /// reading order, since chapters arrive a page at a time from either
    /// end and the order between pages is known only from that.
    struct KnownChapter: Codable, Hashable, Identifiable, Sendable {
        var position: Int
        var chapter: ChekAPI.SourceChapter

        var id: String { chapter.id }
    }

    struct Snapshot: Codable {
        var series: ChekAPI.SourceSeries
        /// How many chapters the source listed when last asked.
        var total: Int?
        /// The chapters seen so far, in reading order: whatever pages were
        /// loaded, not necessarily all of them.
        var chapters: [KnownChapter]
        var savedAt: Date

        /// The chapter after `id` in reading order, if it's been seen.
        func chapter(after id: String) -> KnownChapter? {
            guard let current = chapters.first(where: { $0.chapter.id == id }) else { return nil }
            return chapters.first { $0.position == current.position + 1 }
        }
    }

    /// Application Support rather than Caches: a few kilobytes a series,
    /// and reading offline depends on it.
    static let root = URL.applicationSupportDirectory.appending(path: "SourceSeries", directoryHint: .isDirectory)

    private static func file(server: UUID, source: String, series: String) -> URL {
        root.appending(path: server.uuidString)
            .appending(path: hex(source))
            .appending(path: hex(series) + ".json")
    }

    @concurrent
    static func read(server: UUID, source: String, series: String) async -> Snapshot? {
        guard let data = try? Data(contentsOf: file(server: server, source: source, series: series)) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    /// Keeps the series, and adds `chapters` to the ones already kept.
    /// A chapter seen again replaces its old entry, and one at a position
    /// another now holds is dropped, as when a source renumbers.
    @concurrent
    static func merge(_ series: ChekAPI.SourceSeries, chapters: [KnownChapter], total: Int?, server: UUID, source: String) async {
        var kept = await read(server: server, source: source, series: series.id)?.chapters ?? []
        let ids = Set(chapters.map(\.chapter.id))
        let positions = Set(chapters.map(\.position))
        kept.removeAll { ids.contains($0.chapter.id) || positions.contains($0.position) }
        kept += chapters
        kept.sort { $0.position < $1.position }
        let snapshot = Snapshot(series: series, total: total, chapters: kept, savedAt: .now)
        let url = file(server: server, source: source, series: series.id)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Like `merge`, keeping what's known of the series, or starting from
    /// `fallback` when nothing was kept yet. For checks that list chapters
    /// without loading the series.
    @concurrent
    static func mergeChapters(_ chapters: [KnownChapter], total: Int?, server: UUID, source: String, series fallback: ChekAPI.SourceSeries) async {
        let series = await read(server: server, source: source, series: fallback.id)?.series ?? fallback
        await merge(series, chapters: chapters, total: total, server: server, source: source)
    }

    static func removeAll(for server: UUID) {
        try? FileManager.default.removeItem(at: root.appending(path: server.uuidString))
    }

    private static func hex(_ text: String) -> String {
        Data(text.utf8).map { String(format: "%02x", $0) }.joined()
    }
}
