import Foundation
import Observation
import UIKit

/// Owns what's kept on the device for reading offline: source chapters
/// and server comics, which are downloaded, which are on their way, and
/// the queue that fetches them one at a time so a long series doesn't
/// flood the server or a source's site.
@MainActor
@Observable
final class Downloads {
    /// Something that can be kept on the device: its pages come one by one
    /// from a server, and go in a folder of their own.
    enum Item: Hashable, Sendable {
        case chapter(SourceChapterRef)
        case comic(RemotePublication)

        var ref: PublicationRef {
            switch self {
            case .chapter(let chapter): chapter.ref
            case .comic(let publication): publication.ref
            }
        }

        var server: UUID {
            switch self {
            case .chapter(let chapter): chapter.server
            case .comic(let publication): publication.server
            }
        }

        var title: String {
            switch self {
            case .chapter(let chapter): chapter.chapterTitle
            case .comic(let publication): publication.displayTitle
            }
        }

        var folder: PageFolder {
            switch self {
            case .chapter(let chapter): ChapterFiles.folder(for: chapter)
            case .comic(let publication): PublicationFiles.folder(for: publication)
            }
        }
    }

    enum State: Equatable {
        case none
        case waiting
        case downloading(Double)
        case downloaded
    }

    /// A series with chapters on the device.
    struct DownloadedSeries: Identifiable, Hashable {
        let id: String
        let title: String
        let coverPath: String?
        let chapterCount: Int
    }

    /// What's fully on the device, by what it is.
    private(set) var downloaded: [PublicationRef: Item]
    /// What's queued or being fetched, by reference, with how far along
    /// the one being fetched is.
    private(set) var inProgress: [PublicationRef: Double] = [:]
    /// Why the last download failed, until it's been shown.
    var failure: DisplayError?

    private let servers: ServerStore
    private var queue: [Item] = []
    private var runner: Task<Void, Never>?
    private var current: (item: Item, task: Task<Int, any Error>)?

    init(servers: ServerStore) {
        self.servers = servers
        // Downloads for a server that's gone, removed while the app wasn't
        // running to clean up, go with it now.
        let known = Set(servers.accounts().map(\.id))
        var found: [PublicationRef: Item] = [:]
        for chapter in ChapterFiles.downloaded() where known.contains(chapter.server) {
            found[chapter.ref] = .chapter(chapter)
        }
        for publication in PublicationFiles.downloaded() where known.contains(publication.server) {
            found[publication.ref] = .comic(publication)
        }
        downloaded = found
        for root in [ChapterFiles.root, PublicationFiles.root] {
            for folder in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            where UUID(uuidString: folder.lastPathComponent).map({ !known.contains($0) }) ?? true {
                try? FileManager.default.removeItem(at: folder)
            }
        }
    }

    func state(of ref: PublicationRef) -> State {
        if downloaded[ref] != nil { return .downloaded }
        if let progress = inProgress[ref] {
            return current?.item.ref == ref ? .downloading(progress) : .waiting
        }
        return .none
    }

    func state(of item: Item) -> State {
        state(of: item.ref)
    }

    func isDownloaded(_ ref: PublicationRef) -> Bool {
        downloaded[ref] != nil
    }

    /// Whether anything at all is downloaded.
    var isEmpty: Bool { downloaded.isEmpty }

    /// The series with downloaded chapters from `source` on `server`,
    /// most chapters first, for finding them without the server.
    func series(on server: UUID, source: String) -> [DownloadedSeries] {
        var bySeries: [String: DownloadedSeries] = [:]
        for case .chapter(let chapter) in downloaded.values where chapter.server == server && chapter.source == source {
            let count = (bySeries[chapter.seriesID]?.chapterCount ?? 0) + 1
            bySeries[chapter.seriesID] = DownloadedSeries(id: chapter.seriesID, title: chapter.seriesTitle, coverPath: chapter.seriesCoverPath, chapterCount: count)
        }
        return bySeries.values.sorted { ($0.chapterCount, $1.title) > ($1.chapterCount, $0.title) }
    }

    /// The server comics downloaded from `server`, by series then title,
    /// for finding them without the server.
    func comics(on server: UUID) -> [RemotePublication] {
        var comics: [RemotePublication] = []
        for case .comic(let publication) in downloaded.values where publication.server == server {
            comics.append(publication)
        }
        return comics.sorted { ($0.seriesTitle ?? "", $0.displayTitle) < ($1.seriesTitle ?? "", $1.displayTitle) }
    }

    /// Queues `items`, in the order given, skipping any already here or
    /// on their way.
    func download(_ items: [Item]) {
        for item in items {
            guard downloaded[item.ref] == nil, inProgress[item.ref] == nil else { continue }
            inProgress[item.ref] = 0
            queue.append(item)
        }
        if runner == nil {
            runner = Task { await run() }
        }
    }

    /// Stops a download, or drops it from the queue, keeping nothing.
    func cancel(_ item: Item) {
        queue.removeAll { $0.ref == item.ref }
        if current?.item.ref == item.ref {
            current?.task.cancel()
        } else {
            inProgress[item.ref] = nil
        }
    }

    /// Deletes a download's pages.
    func remove(_ item: Item) {
        item.folder.remove()
        downloaded[item.ref] = nil
    }

    func remove(_ items: [Item]) {
        for item in items {
            remove(item)
        }
    }

    func removeAll() {
        for item in queue {
            inProgress[item.ref] = nil
        }
        queue.removeAll()
        current?.task.cancel()
        ChapterFiles.removeAll()
        PublicationFiles.removeAll()
        downloaded.removeAll()
    }

    /// Downloads for `server`, gone with the server.
    func removeAll(for server: UUID) {
        for item in queue where item.server == server {
            inProgress[item.ref] = nil
        }
        queue.removeAll { $0.server == server }
        if current?.item.server == server {
            current?.task.cancel()
        }
        ChapterFiles.removeAll(for: server)
        PublicationFiles.removeAll(for: server)
        downloaded = downloaded.filter { $0.value.server != server }
    }

    private func run() async {
        // Going to the background mid-download needn't stop it: iOS gives
        // a little while to finish, which one chapter usually fits in.
        var assertion = UIBackgroundTaskIdentifier.invalid
        assertion = UIApplication.shared.beginBackgroundTask(withName: "download") {
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
            let item = queue.removeFirst()
            let task = Task { try await self.fetch(item) }
            current = (item, task)
            do {
                _ = try await task.value
                downloaded[item.ref] = item
            } catch is CancellationError {
                item.folder.remove()
            } catch {
                item.folder.remove()
                failure = DisplayError(
                    title: String(localized: "Couldn't download \(item.title)."),
                    message: DisplayError(error).title
                )
            }
            inProgress[item.ref] = nil
            current = nil
        }
    }

    /// The requests for every page of `item`, in order, through its server.
    private func pageRequests(for item: Item, access: ServerAccess) async throws -> [URLRequest] {
        let client = try await access.client()
        switch item {
        case .chapter(let chapter):
            let chapterID = chapter.chapterID
            let source = chapter.source
            let pages = try await access.request { client throws(ChekError) in
                try await client.pages(ofChapter: chapterID, inSource: source)
            }
            return try pages.map { page in
                guard let request = client.imageRequest(page.url) else { throw ChekError.invalidResponse }
                return request
            }
        case .comic(let publication):
            let id = publication.id
            let count: Int
            if let known = publication.pageCount, known > 0 {
                count = known
            } else {
                count = try await access.request { client throws(ChekError) in try await client.pageCount(of: id) }
            }
            return (0..<count).map { client.pageRequest($0, of: id) }
        }
    }

    /// Fetches every page of `item` through its server, a few at a time,
    /// and marks it complete once all are on disk, giving back how many
    /// pages it has.
    private func fetch(_ item: Item) async throws -> Int {
        let access = ServerAccess(account: item.server, store: servers)
        let requests = try await pageRequests(for: item, access: access)
        guard !requests.isEmpty else {
            throw DisplayError(title: String(localized: "It has no pages to download."))
        }
        let folder = item.folder
        try folder.prepare()
        var done = 0
        try await withThrowingTaskGroup(of: Void.self) { group in
            var next = 0
            func add(_ index: Int) {
                let request = requests[index]
                group.addTask {
                    let data = try await access.data(for: request)
                    try await folder.write(data, page: index)
                }
            }
            // Three at a time: enough to keep up, few enough to be polite.
            while next < min(3, requests.count) {
                add(next)
                next += 1
            }
            while try await group.next() != nil {
                done += 1
                inProgress[item.ref] = Double(done) / Double(requests.count)
                if next < requests.count {
                    add(next)
                    next += 1
                }
            }
        }
        switch item {
        case .chapter(let chapter):
            try ChapterFiles.markComplete(chapter, pageCount: requests.count)
        case .comic(let publication):
            // The cover too, so the comic's cell shows without the server.
            // Not having one is no reason to fail the download.
            if publication.hasCover, let client = try? await access.client(),
               let data = try? await access.data(for: client.coverRequest(of: publication.id)) {
                try? data.write(to: PublicationFiles.cover(of: publication.id, on: publication.server), options: .atomic)
            }
            try PublicationFiles.markComplete(publication, pageCount: requests.count)
        }
        return requests.count
    }
}
