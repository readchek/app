import Foundation

/// What a source last said about a series, kept on the device so the
/// series still shows, and the next chapter is still known, when the
/// server can't be reached, as when reading downloaded chapters offline.
nonisolated enum SeriesCache {
    struct Snapshot: Codable {
        var series: ChekAPI.SourceSeries
        var chapters: [ChekAPI.SourceChapter]
        var savedAt: Date
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

    @concurrent
    static func write(_ series: ChekAPI.SourceSeries, chapters: [ChekAPI.SourceChapter], server: UUID, source: String) async {
        let url = file(server: server, source: source, series: series.id)
        guard let data = try? JSONEncoder().encode(Snapshot(series: series, chapters: chapters, savedAt: .now)) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func removeAll(for server: UUID) {
        try? FileManager.default.removeItem(at: root.appending(path: server.uuidString))
    }

    private static func hex(_ text: String) -> String {
        Data(text.utf8).map { String(format: "%02x", $0) }.joined()
    }
}
