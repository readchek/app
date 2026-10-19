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

    /// What the reader needs to open `publication`, starting at your
    /// latest place on any device.
    func readingItem(for publication: RemotePublication) async throws(DisplayError) -> ReadingItem {
        guard let client = servers.client(for: publication.server) else {
            throw DisplayError(ChekError.unauthorized)
        }
        let state = readingState(for: publication)
        await refresh(state, from: publication)

        let content: ReadingItem.Content
        switch publication.kind {
        case .comic:
            content = .source(.pages(ChekPageSource(client: client, publication: publication.id, knownPageCount: publication.pageCount)))
        case .book where publication.format == "epub":
            // EPUBs stream entry by entry with range requests.
            content = .source(.remote(
                client.fileURL(of: publication.id),
                RemoteOptions(identifier: publication.ref.storageKey) { request in client.authorize(request) }
            ))
        case .book:
            content = .download(Download(
                request: client.fileRequest(of: publication.id),
                destination: ServerFiles.file(for: publication.id, format: publication.format, account: publication.server)
            ))
        }
        return ReadingItem(
            ref: publication.ref,
            title: publication.displayTitle,
            subtitle: publication.seriesTitle,
            kind: publication.kind,
            content: content,
            startLocation: state.savedLocation
        )
    }

    /// Brings the device's copy of your place up to date with the server's
    /// before opening. Your place here wins until you choose otherwise.
    private func refresh(_ state: RemoteReadingState, from publication: RemotePublication) async {
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
        for state in pending where prompts[state.ref] == nil {
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
