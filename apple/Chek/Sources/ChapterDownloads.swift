import Foundation
import Observation
import UIKit

/// Owns the source chapters kept on the device for reading offline:
/// which are downloaded, which are on their way, and the queue that
/// fetches them one chapter at a time so a long series doesn't flood the
/// source's site.
@MainActor
@Observable
final class ChapterDownloads {
    enum State: Equatable {
        case none
        case waiting
        case downloading(Double)
        case downloaded
    }

    /// Chapters fully on the device, with what's known about each.
    private(set) var downloaded: [SourceChapterRef: ChapterFiles.Note]

    /// A series with chapters on the device.
    struct DownloadedSeries: Identifiable, Hashable {
        let id: String
        let title: String
        let coverPath: String?
        let chapterCount: Int
    }
    /// Chapters queued or being fetched, by storage key, with how far
    /// along the one being fetched is.
    private(set) var inProgress: [String: Double] = [:]
    /// Why the last download failed, until it's been shown.
    var failure: DisplayError?

    private let servers: ServerStore
    private var queue: [SourceChapterRef] = []
    private var runner: Task<Void, Never>?
    private var current: (chapter: SourceChapterRef, task: Task<Int, any Error>)?

    init(servers: ServerStore) {
        self.servers = servers
        downloaded = ChapterFiles.downloaded()
    }

    func state(of chapter: SourceChapterRef) -> State {
        let key = chapter.ref.storageKey
        if downloaded[chapter] != nil { return .downloaded }
        if let progress = inProgress[key] {
            return current?.chapter.ref == chapter.ref ? .downloading(progress) : .waiting
        }
        return .none
    }

    func isDownloaded(_ chapter: SourceChapterRef) -> Bool {
        downloaded[chapter] != nil
    }

    /// Whether anything at all is downloaded.
    var isEmpty: Bool { downloaded.isEmpty }

    /// The series with downloaded chapters from `source` on `server`,
    /// most chapters first, for finding them without the server.
    func series(on server: UUID, source: String) -> [DownloadedSeries] {
        var bySeries: [String: DownloadedSeries] = [:]
        for (chapter, note) in downloaded where chapter.server == server && chapter.source == source {
            let count = (bySeries[note.seriesID]?.chapterCount ?? 0) + 1
            bySeries[note.seriesID] = DownloadedSeries(id: note.seriesID, title: note.seriesTitle, coverPath: note.seriesCoverPath, chapterCount: count)
        }
        return bySeries.values.sorted { ($0.chapterCount, $1.title) > ($1.chapterCount, $0.title) }
    }

    /// Queues `chapters`, in the order given, skipping any already here
    /// or on their way.
    func download(_ chapters: [SourceChapterRef]) {
        for chapter in chapters {
            let key = chapter.ref.storageKey
            guard downloaded[chapter] == nil, inProgress[key] == nil else { continue }
            inProgress[key] = 0
            queue.append(chapter)
        }
        if runner == nil {
            runner = Task { await run() }
        }
    }

    /// Stops a download, or drops it from the queue, keeping nothing.
    func cancel(_ chapter: SourceChapterRef) {
        let key = chapter.ref.storageKey
        queue.removeAll { $0.ref == chapter.ref }
        if current?.chapter.ref == chapter.ref {
            current?.task.cancel()
        } else {
            inProgress[key] = nil
        }
    }

    /// Deletes a downloaded chapter's pages.
    func remove(_ chapter: SourceChapterRef) {
        ChapterFiles.remove(chapter)
        downloaded[chapter] = nil
    }

    func remove(_ chapters: [SourceChapterRef]) {
        for chapter in chapters {
            remove(chapter)
        }
    }

    func removeAll() {
        for chapter in queue {
            inProgress[chapter.ref.storageKey] = nil
        }
        queue.removeAll()
        current?.task.cancel()
        ChapterFiles.removeAll()
        downloaded.removeAll()
    }

    /// Downloads for `server`, gone with the server.
    func removeAll(for server: UUID) {
        for chapter in queue where chapter.server == server {
            inProgress[chapter.ref.storageKey] = nil
        }
        queue.removeAll { $0.server == server }
        if current?.chapter.server == server {
            current?.task.cancel()
        }
        ChapterFiles.removeAll(for: server)
        downloaded = downloaded.filter { $0.key.server != server }
    }

    private func run() async {
        // Going to the background mid-chapter needn't stop it: iOS gives
        // a little while to finish, which one chapter usually fits in.
        var assertion = UIBackgroundTaskIdentifier.invalid
        assertion = UIApplication.shared.beginBackgroundTask(withName: "chapter download") {
            self.current?.task.cancel()
            UIApplication.shared.endBackgroundTask(assertion)
            assertion = .invalid
        }
        defer {
            runner = nil
            if assertion != .invalid {
                UIApplication.shared.endBackgroundTask(assertion)
            }
        }
        while !queue.isEmpty {
            let chapter = queue.removeFirst()
            let key = chapter.ref.storageKey
            let task = Task { try await self.fetch(chapter) }
            current = (chapter, task)
            do {
                let pageCount = try await task.value
                downloaded[chapter] = ChapterFiles.Note(chapter, pageCount: pageCount)
            } catch is CancellationError {
                ChapterFiles.remove(chapter)
            } catch {
                ChapterFiles.remove(chapter)
                failure = DisplayError(
                    title: String(localized: "Couldn't download \(chapter.chapterTitle)."),
                    message: DisplayError(error).title
                )
            }
            inProgress[key] = nil
            current = nil
        }
    }

    /// Fetches every page of `chapter` through its server, a few at a
    /// time, and marks the chapter complete once all are on disk, giving
    /// back how many pages it has.
    private func fetch(_ chapter: SourceChapterRef) async throws -> Int {
        let access = ServerAccess(account: chapter.server, store: servers)
        let chapterID = chapter.chapterID
        let source = chapter.source
        let pages = try await access.request { client throws(ChekError) in
            try await client.pages(ofChapter: chapterID, inSource: source)
        }
        guard !pages.isEmpty else {
            throw DisplayError(title: String(localized: "The source lists no pages for it."))
        }
        let folder = ChapterFiles.folder(for: chapter)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let key = chapter.ref.storageKey
        var done = 0
        try await withThrowingTaskGroup(of: Void.self) { group in
            var next = 0
            func add(_ index: Int) {
                let path = pages[index].url
                group.addTask {
                    let client = try await access.client()
                    guard let request = client.imageRequest(path) else { throw ChekError.invalidResponse }
                    let data = try await access.data(for: request)
                    try await Self.write(data, to: ChapterFiles.page(index, of: chapter))
                }
            }
            // Three at a time: enough to keep up, few enough to be polite.
            while next < min(3, pages.count) {
                add(next)
                next += 1
            }
            while try await group.next() != nil {
                done += 1
                inProgress[key] = Double(done) / Double(pages.count)
                if next < pages.count {
                    add(next)
                    next += 1
                }
            }
        }
        try ChapterFiles.markComplete(chapter, pageCount: pages.count)
        return pages.count
    }

    @concurrent
    nonisolated private static func write(_ data: Data, to url: URL) async throws {
        try data.write(to: url, options: .atomic)
    }
}
