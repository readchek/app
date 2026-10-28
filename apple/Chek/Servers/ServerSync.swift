import ChekReader
import Foundation
import Observation
import SwiftData

/// A place saved on another device that differs from the one here.
struct OtherDevicePosition: Equatable {
    let locator: Locator
    let device: String?
    let updatedAt: Date?
    let revision: Int64
}

/// Opens server publications and keeps your places in them in step with
/// the server.
///
/// Places are saved on the device first by ``ProgressStore``; this uploads
/// them a moment later, so a run of page turns sends one request. When
/// another device saved a different place, it asks rather than choosing,
/// as the server's contract requires: ``prompts`` holds the question until
/// you answer it in the reader.
@MainActor
@Observable
final class ServerSync {
    /// Places from other devices waiting for you to choose, by publication.
    private(set) var prompts: [PublicationRef: OtherDevicePosition] = [:]

    private let servers: ServerStore
    private let progress: ProgressStore
    private let context: ModelContext
    @ObservationIgnored private var uploadTask: Task<Void, Never>?

    init(servers: ServerStore, progress: ProgressStore, context: ModelContext) {
        self.servers = servers
        self.progress = progress
        self.context = context
    }

    // MARK: - Opening

    /// Whether `server`'s session has ended, so opening from it needs you
    /// to sign in again.
    func isSignedOut(of server: UUID) -> Bool {
        servers.state(of: server) == .signedOut
    }

    /// What the reader needs to open `publication`, starting at your
    /// latest place on any device.
    func readingItem(for publication: RemotePublication) async throws(DisplayError) -> ReadingItem {
        let isDownloaded = publication.kind == .comic && PublicationFiles.folder(for: publication).isComplete
        let client = servers.client(for: publication.server)
        guard client != nil || isDownloaded else {
            throw DisplayError(ChekError.unauthorized)
        }
        let state = readingState(for: publication)
        if client != nil {
            await refresh(state, from: publication)
        }

        let content: ReadingItem.Content
        switch publication.kind {
        case .comic:
            content = .source(.pages(ChekPageSource(server: ServerAccess(account: publication.server, store: servers), publication: publication.id, knownPageCount: publication.pageCount)))
        case .book where publication.format == "epub":
            guard let client else { throw DisplayError(ChekError.unauthorized) }
            // EPUBs stream entry by entry with range requests.
            content = .source(.remote(
                client.fileURL(of: publication.id),
                RemoteOptions(identifier: publication.ref.storageKey) { request in client.authorize(request) }
            ))
        case .book:
            guard let client else { throw DisplayError(ChekError.unauthorized) }
            content = .download(Download(
                request: client.fileRequest(of: publication.id),
                destination: ServerFiles.file(for: publication.id, format: publication.format, account: publication.server)
            ))
        }
        var item = ReadingItem(
            ref: publication.ref,
            title: publication.displayTitle,
            subtitle: publication.seriesTitle,
            kind: publication.kind,
            content: content,
            startLocation: state.savedLocation
        )
        if let series = publication.seriesID {
            item.seriesKey = "server/\(publication.server.uuidString)/series/\(series)"
        }
        item.isOnDevice = isDownloaded
        item.serverPublication = publication
        if publication.seriesID != nil {
            item.series = publication.seriesTitle
        }
        return item
    }

    /// What the reader needs to open a chapter straight from a source,
    /// starting where you left it on this device. A source of comics opens
    /// at once and fetches pages as they're read; anything else is asked
    /// what the chapter is first, since it may be a book.
    func readingItem(for chapter: SourceChapterRef) async throws(DisplayError) -> ReadingItem {
        let client = servers.client(for: chapter.server)
        if ChapterFiles.downloadedPageCount(of: chapter) != nil || SourceFormats.readsOnlyPages(chapter.source, on: chapter.server) {
            guard client != nil || ChapterFiles.downloadedPageCount(of: chapter) != nil else {
                throw DisplayError(ChekError.unauthorized)
            }
            return pagesItem(for: chapter)
        }
        guard client != nil else {
            if let kept = ChapterBooks.kept(for: chapter) {
                return bookItem(for: chapter, content: .source(.file(kept.url)), rights: ChapterBooks.rights(of: chapter), isOnDevice: true)
            }
            throw DisplayError(ChekError.unauthorized)
        }
        let content: ChekAPI.ChapterContent
        do {
            content = try await servers.request(chapter.server) { client throws(ChekError) in
                try await client.chapterContent(chapter.chapterID, inSource: chapter.source)
            }
        } catch {
            // The book fetched last time still reads without the server.
            if !error.isCancellation, let kept = ChapterBooks.kept(for: chapter) {
                return bookItem(for: chapter, content: .source(.file(kept.url)), rights: ChapterBooks.rights(of: chapter), isOnDevice: true)
            }
            // An older server has no content route, and reads only pages.
            if case .notFound = error {
                return pagesItem(for: chapter)
            }
            throw DisplayError(error)
        }
        ChapterBooks.saveRights(content.rights, of: chapter)
        // The reader is chosen by the format the server names, never by
        // the file's address.
        guard content.format != .images, let file = content.file else {
            return pagesItem(for: chapter)
        }
        let destination = ChapterBooks.file(file, format: content.format, of: chapter)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            ChapterBooks.removeOthers(of: chapter, keeping: destination)
            return bookItem(for: chapter, content: .source(.file(destination)), rights: content.rights, isOnDevice: true)
        }
        guard let client = servers.client(for: chapter.server), var request = client.imageRequest(file.url) else {
            throw DisplayError(ChekError.invalidResponse)
        }
        // Books can be large, and the server fetches them from the site
        // before sending any.
        request.timeoutInterval = 300
        return bookItem(for: chapter, content: .download(Download(request: request, destination: destination)), rights: content.rights, isOnDevice: false)
    }

    private func pagesItem(for chapter: SourceChapterRef) -> ReadingItem {
        let state = progress.sourceState(for: chapter)
        var item = ReadingItem(
            ref: chapter.ref,
            title: chapter.chapterTitle,
            subtitle: chapter.seriesTitle,
            kind: .comic,
            content: .source(.pages(SourcePageSource(
                server: ServerAccess(account: chapter.server, store: servers),
                chapter: chapter,
                readingProgression: chapter.isRightToLeft ? .rightToLeft : .auto
            ))),
            startLocation: state.savedLocation
        )
        item.sourceChapter = chapter
        item.series = chapter.seriesTitle
        item.seriesKey = "source/\(chapter.server.uuidString)/\(chapter.source)/\(chapter.seriesID)"
        item.isOnDevice = ChapterFiles.downloadedPageCount(of: chapter) != nil
        return item
    }

    private func bookItem(for chapter: SourceChapterRef, content: ReadingItem.Content, rights: ChekAPI.Rights?, isOnDevice: Bool) -> ReadingItem {
        let state = progress.sourceState(for: chapter)
        var item = ReadingItem(
            ref: chapter.ref,
            title: chapter.chapterTitle,
            subtitle: chapter.seriesTitle,
            kind: .book,
            content: content,
            startLocation: state.savedLocation
        )
        item.sourceChapter = chapter
        item.series = chapter.seriesTitle
        item.seriesKey = "source/\(chapter.server.uuidString)/\(chapter.source)/\(chapter.seriesID)"
        item.isOnDevice = isOnDevice
        item.rights = rights.flatMap { $0.isEmpty ? nil : $0 }
        return item
    }

    /// Asks sources for the covers of series you've read chapters of but
    /// whose cover isn't kept, such as places saved before covers were,
    /// so Continue Reading shows them. Each series is asked for once.
    func fillMissingSourceCovers() async {
        let missing = (try? context.fetch(FetchDescriptor<SourceReadingState>(predicate: #Predicate { $0.seriesCoverPath == nil }))) ?? []
        var seen = Set<String>()
        for state in missing {
            let key = "\(state.serverID)/\(state.sourceID)/\(state.seriesID)"
            guard seen.insert(key).inserted, servers.state(of: state.serverID) == .signedIn else { continue }
            let server = state.serverID
            let source = state.sourceID
            let seriesID = state.seriesID
            guard let series = try? await servers.request(server, { client throws(ChekError) in
                try await client.series(seriesID, inSource: source)
            }) else { continue }
            progress.updateSourceSeries(series, server: server, source: source)
        }
    }

    // MARK: - Series order

    /// What comes before or after something in its series.
    enum Neighbor<Item: Equatable>: Equatable {
        case found(Item)
        /// There's nothing further that way: it's the series' first or last.
        case end
        /// The server couldn't say and nothing on the device can either.
        case unknown
    }

    /// The chapter after `chapter`, from the server, or from what it said
    /// last time when it can't be reached.
    func chapter(after chapter: SourceChapterRef) async -> Neighbor<SourceChapterRef> {
        await neighbor(of: chapter, toward: .oldestFirst)
    }

    /// The chapter before `chapter`, found the same way as the one after.
    func chapter(before chapter: SourceChapterRef) async -> Neighbor<SourceChapterRef> {
        await neighbor(of: chapter, toward: .newestFirst)
    }

    /// The chapter next to `chapter` going the way `order` reads: the one
    /// after it oldest first, the one before it newest first.
    private func neighbor(of chapter: SourceChapterRef, toward order: ChekClient.ChapterOrder) async -> Neighbor<SourceChapterRef> {
        let seriesID = chapter.seriesID
        let source = chapter.source
        let chapterID = chapter.chapterID
        let neighbor: ChekAPI.SourceChapter
        do {
            let page = try await servers.request(chapter.server) { client throws(ChekError) in
                try await client.chapterPage(ofSeries: seriesID, inSource: source, order: order, after: chapterID, limit: 1)
            }
            guard let found = page.items.first else { return .end }
            neighbor = found
        } catch .notFound {
            // The source no longer lists this chapter.
            return .unknown
        } catch {
            // Offline: what was seen of the series before may know.
            guard let snapshot = await SeriesCache.read(server: chapter.server, source: source, series: seriesID),
                  let current = snapshot.chapter(containing: chapterID) else {
                return .unknown
            }
            switch order {
            case .oldestFirst:
                if let following = snapshot.chapter(after: chapterID) {
                    neighbor = following.chapter
                } else if let total = snapshot.total, current.position + max(current.chapter.releases?.count ?? 1, 1) > total {
                    return .end
                } else {
                    return .unknown
                }
            case .newestFirst:
                if let preceding = snapshot.chapter(before: chapterID) {
                    neighbor = preceding.chapter
                } else if current.position <= 1 {
                    return .end
                } else {
                    return .unknown
                }
            }
        }
        return .found(SourceChapterRef(
            server: chapter.server,
            source: chapter.source,
            seriesID: chapter.seriesID,
            seriesTitle: chapter.seriesTitle,
            chapterID: neighbor.id,
            chapterTitle: neighbor.displayTitle,
            isRightToLeft: chapter.isRightToLeft,
            seriesCoverPath: chapter.seriesCoverPath
        ))
    }

    /// The publications either side of `publication` in its series, in
    /// the server's reading order: numbered ones by number, then the rest
    /// by title.
    ///
    /// The series is read a page at a time from its start until the one
    /// after `publication` turns up, since the server's pages only run
    /// forward. Even a long manga is a handful of pages.
    func neighbors(of publication: RemotePublication) async -> (previous: Neighbor<RemotePublication>, next: Neighbor<RemotePublication>) {
        guard let series = publication.seriesID else { return (.end, .end) }
        let server = publication.server
        var cursor: String?
        var previous: RemotePublication?
        var isFound = false
        var before: Neighbor<RemotePublication> {
            previous.map(Neighbor<RemotePublication>.found) ?? .end
        }
        // A bound on pages, so a server that keeps answering with a cursor
        // can't keep this going forever.
        for _ in 0..<100 {
            let page: ChekAPI.Page<ChekAPI.PublicationSummary>
            do {
                page = try await servers.request(server) { [cursor] client throws(ChekError) in
                    try await client.publications(inSeries: series, cursor: cursor)
                }
            } catch {
                return (isFound ? before : .unknown, .unknown)
            }
            for summary in page.items {
                let item = RemotePublication(summary, server: server)
                if isFound {
                    return (before, .found(item))
                }
                if item.id == publication.id {
                    isFound = true
                } else {
                    previous = item
                }
            }
            guard let next = page.nextCursor else { break }
            cursor = next
        }
        guard isFound else { return (.unknown, .unknown) }
        return (before, .end)
    }

    /// Brings the device's copy of your place up to date with the server's
    /// before opening. Your place here wins until you choose otherwise.
    private func refresh(_ state: RemoteReadingState, from publication: RemotePublication) async {
        // Other people's places on the shared demo account aren't yours.
        guard publication.server != DemoMode.accountID else { return }
        guard let remote = try? await servers.request(publication.server, { client throws(ChekError) in
            try await client.progress(of: publication.id)
        }) else { return }
        guard remote.revision > state.revision, let locator = remote.locator else { return }
        guard let local = state.savedLocation else {
            // Nothing here yet, so start where you left off elsewhere.
            adopt(remote, into: state)
            return
        }
        if local.isNear(locator) {
            state.revision = remote.revision
            try? context.save()
        } else {
            prompts[publication.ref] = OtherDevicePosition(locator: locator, device: remote.device, updatedAt: remote.updatedAt, revision: remote.revision)
        }
    }

    private func adopt(_ remote: ChekAPI.Progress, into state: RemoteReadingState) {
        state.location = remote.locator.flatMap { try? JSONEncoder().encode($0) }
        state.progress = remote.locator?.locations.totalProgression
        state.revision = remote.revision
        state.needsUpload = false
        try? context.save()
    }

    /// The device's record of `publication`, made the first time it opens.
    private func readingState(for publication: RemotePublication) -> RemoteReadingState {
        if let state = progress.readingState(publication.ref) {
            // Titles and covers change on the server; keep them current.
            state.title = publication.title
            state.numberLabel = publication.numberLabel
            state.hasCover = publication.hasCover
            return state
        }
        let state = RemoteReadingState(
            serverID: publication.server,
            publicationID: publication.id,
            title: publication.title,
            seriesID: publication.seriesID,
            seriesTitle: publication.seriesTitle,
            numberLabel: publication.numberLabel,
            format: publication.format,
            hasCover: publication.hasCover
        )
        context.insert(state)
        try? context.save()
        return state
    }

    // MARK: - Choosing between devices

    /// Keeps the place on this device; the next upload replaces the other.
    func keepThisDevicePosition(for ref: PublicationRef) {
        guard let prompt = prompts.removeValue(forKey: ref), let state = progress.readingState(ref) else { return }
        state.revision = prompt.revision
        state.needsUpload = true
        try? context.save()
        scheduleUpload()
    }

    /// Takes the other device's place. The reader moves there, and the
    /// move is recorded like any page turn.
    func useOtherDevicePosition(for ref: PublicationRef) -> Locator? {
        guard let prompt = prompts.removeValue(forKey: ref), let state = progress.readingState(ref) else { return nil }
        state.revision = prompt.revision
        try? context.save()
        return prompt.locator
    }

    // MARK: - Uploading

    /// Uploads waiting places after a short pause.
    func scheduleUpload() {
        uploadTask?.cancel()
        uploadTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await uploadPending()
        }
    }

    /// Uploads every place that changed here, now.
    func uploadPending() async {
        let descriptor = FetchDescriptor<RemoteReadingState>(predicate: #Predicate { $0.needsUpload })
        guard let pending = try? context.fetch(descriptor) else { return }
        // The demo account is shared by everyone trying the app, so places
        // read there stay on this device.
        for state in pending where prompts[state.ref] == nil && state.serverID != DemoMode.accountID {
            await upload(state)
        }
    }

    private func upload(_ state: RemoteReadingState) async {
        guard let locator = state.savedLocation, let sent = state.location else { return }
        let ref = state.ref
        let publication = state.publicationID
        let expected = state.revision
        do {
            let saved = try await servers.request(state.serverID) { client throws(ChekError) in
                try await client.saveProgress(locator, of: publication, expectedRevision: expected)
            }
            state.revision = saved.revision
            // A page turned during the upload is still waiting.
            if state.location == sent {
                state.needsUpload = false
            }
        } catch .progressConflict(let current) {
            if let theirs = current.locator, !theirs.isNear(locator) {
                prompts[ref] = OtherDevicePosition(locator: theirs, device: current.device, updatedAt: current.updatedAt, revision: current.revision)
            } else {
                // Both devices are at the same place; just catch up.
                state.revision = current.revision
                state.needsUpload = state.location != sent
            }
        } catch .server(status: 403, "demo_account") {
            // A shared demo account keeps no one's place, so there's no
            // point asking again; the place stays on this device.
            state.needsUpload = false
        } catch {
            // Offline or signed out: the place stays waiting for next time.
            return
        }
        try? context.save()
    }
}

extension Locator {
    /// Whether two places are on about the same page, so moving between
    /// them isn't worth asking about.
    func isNear(_ other: Locator) -> Bool {
        if let mine = locations.totalProgression, let theirs = other.locations.totalProgression {
            return abs(mine - theirs) < 0.002
        }
        return href == other.href && abs((locations.progression ?? 0) - (other.locations.progression ?? 0)) < 0.01
    }
}
