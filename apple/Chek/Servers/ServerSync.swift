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
        return item
    }

    /// What the reader needs to open a chapter straight from a source,
    /// starting where you left it on this device.
    func readingItem(for chapter: SourceChapterRef) throws(DisplayError) -> ReadingItem {
        guard servers.client(for: chapter.server) != nil || ChapterFiles.downloadedPageCount(of: chapter) != nil else {
            throw DisplayError(ChekError.unauthorized)
        }
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
        item.seriesKey = "source/\(chapter.server.uuidString)/\(chapter.source)/\(chapter.seriesID)"
        item.isOnDevice = ChapterFiles.downloadedPageCount(of: chapter) != nil
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

    /// The chapter after `chapter` in its series, in reading order, or nil
    /// at the last one or when the list can't be read.
    /// What follows a chapter in its series.
    enum NextChapter: Equatable {
        case next(SourceChapterRef)
        /// The chapter is the series' last.
        case end
        /// The server couldn't say and nothing on the device can either.
        case unknown
    }

    /// The chapter after `chapter`, from the server, or from what it said
    /// last time when it can't be reached.
    func chapter(after chapter: SourceChapterRef) async -> NextChapter {
        let seriesID = chapter.seriesID
        let source = chapter.source
        var chapters = try? await servers.request(chapter.server) { client throws(ChekError) in
            try await client.chapters(ofSeries: seriesID, inSource: source)
        }
        if chapters == nil {
            chapters = await SeriesCache.read(server: chapter.server, source: source, series: seriesID)?.chapters
        }
        guard let chapters, let index = chapters.firstIndex(where: { $0.id == chapter.chapterID }) else {
            return .unknown
        }
        guard chapters.indices.contains(index + 1) else { return .end }
        let next = chapters[index + 1]
        return .next(SourceChapterRef(
            server: chapter.server,
            source: chapter.source,
            seriesID: chapter.seriesID,
            seriesTitle: chapter.seriesTitle,
            chapterID: next.id,
            chapterTitle: next.displayTitle,
            isRightToLeft: chapter.isRightToLeft,
            seriesCoverPath: chapter.seriesCoverPath
        ))
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
