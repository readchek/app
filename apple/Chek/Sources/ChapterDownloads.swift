import Foundation
import Observation

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

    /// Chapters fully on the device, by ``PublicationRef/storageKey``.
    private(set) var downloaded: Set<String>
    /// Chapters queued or being fetched, by storage key, with how far
    /// along the one being fetched is.
    private(set) var inProgress: [String: Double] = [:]
    /// Why the last download failed, until it's been shown.
    var failure: DisplayError?

    private let servers: ServerStore
    private var queue: [SourceChapterRef] = []
    private var runner: Task<Void, Never>?
    private var current: (chapter: SourceChapterRef, task: Task<Void, any Error>)?

    init(servers: ServerStore) {
        self.servers = servers
        downloaded = ChapterFiles.downloadedKeys()
    }

    func state(of chapter: SourceChapterRef) -> State {
        let key = chapter.ref.storageKey
        if downloaded.contains(key) { return .downloaded }
        if let progress = inProgress[key] {
            return current?.chapter.ref == chapter.ref ? .downloading(progress) : .waiting
        }
        return .none
    }

    func isDownloaded(_ chapter: SourceChapterRef) -> Bool {
        downloaded.contains(chapter.ref.storageKey)
    }

    /// Queues `chapters`, in the order given, skipping any already here
    /// or on their way.
    func download(_ chapters: [SourceChapterRef]) {
        for chapter in chapters {
            let key = chapter.ref.storageKey
            guard !downloaded.contains(key), inProgress[key] == nil else { continue }
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
        downloaded.remove(chapter.ref.storageKey)
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
        downloaded = downloaded.filter { !$0.hasPrefix("source/\(server.uuidString)/") }
    }

    private func run() async {
        defer { runner = nil }
        while !queue.isEmpty {
            let chapter = queue.removeFirst()
            let key = chapter.ref.storageKey
            let task = Task { try await self.fetch(chapter) }
            current = (chapter, task)
            do {
                try await task.value
                downloaded.insert(key)
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
    /// time, and marks the chapter complete once all are on disk.
    private func fetch(_ chapter: SourceChapterRef) async throws {
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
    }

    @concurrent
    nonisolated private static func write(_ data: Data, to url: URL) async throws {
        try data.write(to: url, options: .atomic)
    }
}
