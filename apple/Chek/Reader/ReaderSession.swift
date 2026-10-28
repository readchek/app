import ChekReader
import Foundation
import Observation

/// One time reading one publication: the reader engine, whether the
/// controls are showing and which panel is open.
///
/// The reader's position lives in ``controller`` and is read only by the
/// small views that show or save it, so turning a page doesn't redraw the
/// screen around the page.
@MainActor
@Observable
final class ReaderSession {
    enum Phase: Equatable {
        /// Fetching a file that can't stream, from 0 to 1 when the size is known.
        case downloading(Double?)
        case reading
        case failed(DisplayError)
    }

    enum Panel: String, Identifiable {
        case contents, appearance

        var id: Self { self }
    }

    let item: ReadingItem
    let controller: ReaderController
    private(set) var phase: Phase
    private(set) var isShowingControls = true
    var panel: Panel?
    /// Whether the sign-in form is up, for a server that ended its session
    /// while you were reading from it.
    var isSigningIn = false
    /// What comes after this in its series, looked up as it opens so the
    /// way on is ready before you reach the last page.
    private(set) var next: NeighborLookup = .looking
    /// What comes before it, for going back a chapter.
    private(set) var previous: NeighborLookup = .looking
    /// Whether a comic has been turned past its last page, which shows what
    /// you've finished and what's next, off the artwork. Turning on again
    /// opens it.
    private(set) var isShowingChapterEnd = false

    init(item: ReadingItem, preferences: ReaderPreferences) {
        self.item = item
        controller = ReaderController(preferences: preferences)
        switch item.content {
        case .source: phase = .reading
        case .download: phase = .downloading(nil)
        }
    }

    /// Opens the publication, fetching it first if it has to be.
    func open() async {
        let source: PublicationSource
        switch item.content {
        case .source(let ready):
            source = ready
        case .download(let download):
            phase = .downloading(nil)
            do {
                source = .file(try await fetch(download))
            } catch is CancellationError {
                return
            } catch {
                phase = .failed(DisplayError(error))
                return
            }
        }
        phase = .reading
        // Failures show through the controller's state.
        try? await controller.open(source, at: item.startLocation)
    }

    /// Opens the publication again at the current place, as after signing
    /// in to its server again, so pages that failed load afresh.
    func reopen() async {
        let place = controller.location
        if case .source(let source) = item.content, let place {
            phase = .reading
            try? await controller.open(source, at: place)
        } else {
            await open()
        }
    }

    /// Looks up what's either side of this in its series.
    func findNeighbors(with finder: NeighborFinder) async {
        if next != .looking || previous != .looking {
            next = .looking
            previous = .looking
        }
        let found = await finder.neighbors(of: item)
        next = found.next
        previous = found.previous
    }

    /// Whether the last page is showing. Only the views that change on it
    /// read it, since it reads the location.
    var isOnLastPage: Bool {
        guard let location = controller.location else { return false }
        if let count = controller.positions?.count, count > 0,
           let position = location.locations.position, position >= count {
            return true
        }
        // Text that reflows has more screens than positions near its end,
        // so its last screen can still be on an earlier position. How far
        // through the book it is says so instead.
        return showsTextSettings && (location.locations.totalProgression ?? 0) >= ReadingStatus.finishedThreshold
    }

    /// What a page turn past the last page goes on to, if anything. A comic
    /// first steps onto its chapter end, as Mihon does, so the next one
    /// never opens by surprise. A book already says what's next on its
    /// last page, so it goes straight on.
    func turnedPastEnd() -> ReadingTarget? {
        guard isOnLastPage, next != .none else { return nil }
        if item.kind == .comic, !isShowingChapterEnd {
            isShowingChapterEnd = true
            hideControls()
            return nil
        }
        return next.target
    }

    /// Back from the chapter end to the page, after turning back a page.
    func leaveChapterEnd() {
        isShowingChapterEnd = false
    }

    /// Text settings only reach text that reflows, so comics and PDFs
    /// only offer the page turn.
    var showsTextSettings: Bool {
        item.kind == .book && controller.format != .pdf
    }

    func toggleControls() {
        isShowingControls.toggle()
        if !isShowingControls {
            panel = nil
        }
    }

    /// Hides the controls once you start reading, as turning a page in
    /// Books does.
    func hideControls() {
        guard panel == nil else { return }
        isShowingControls = false
    }

    func show(_ panel: Panel) {
        self.panel = panel
    }

    /// Moves to a table of contents entry and gets out of the way.
    func go(to link: ChekReader.Link) async {
        panel = nil
        isShowingControls = false
        await controller.go(to: link)
    }

    private func fetch(_ download: Download) async throws -> URL {
        if FileManager.default.fileExists(atPath: download.destination.path(percentEncoded: false)) {
            return download.destination
        }
        let run = DownloadRun(download: download, resumeData: Self.partialDownloads.removeValue(forKey: download.destination)) { [weak self] fraction in
            Task { @MainActor in
                guard let self, case .downloading = self.phase else { return }
                self.phase = .downloading(fraction)
            }
        }
        let file: URL
        do {
            file = try await run.file()
        } catch let error as DownloadRun.Failure {
            // What arrived is kept, so closing the reader by accident, or
            // losing the connection, doesn't start over next time.
            if let resumeData = error.resumeData {
                Self.partialDownloads[download.destination] = resumeData
            }
            if error.isCancellation {
                throw CancellationError()
            }
            if error.status == 401 {
                throw DisplayError(ChekError.unauthorized)
            }
            throw DisplayError(
                title: String(localized: "Couldn't Download This Book"),
                message: String(localized: "Check your internet connection and try again.")
            )
        }
        try FileManager.default.createDirectory(at: download.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: download.destination)
        try FileManager.default.moveItem(at: file, to: download.destination)
        return download.destination
    }

    /// Downloads that stopped partway, by where they were going, so the
    /// next open of the same publication picks up where they left off.
    private static var partialDownloads: [URL: Data] = [:]
}

/// One download of a publication's file, reporting how much has arrived
/// in steps of a percent so the progress ring doesn't redraw for every
/// packet, and keeping what arrived when it's stopped.
private nonisolated final class DownloadRun: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    struct Failure: Error {
        var status: Int?
        var isCancellation = false
        /// What the system kept of the download, to resume it from.
        var resumeData: Data?
    }

    private let download: Download
    private let resumeData: Data?
    private let report: @Sendable (Double) -> Void
    // Only touched from the session's delegate queue, which is serial.
    private var reported = -1.0
    private var finished: Result<URL, Failure>?
    private var continuation: CheckedContinuation<URL, any Error>?
    private var task: URLSessionDownloadTask?
    private let lock = NSLock()

    init(download: Download, resumeData: Data?, report: @escaping @Sendable (Double) -> Void) {
        self.download = download
        self.resumeData = resumeData
        self.report = report
    }

    /// The downloaded file, in a temporary place, once it's all arrived.
    func file() async throws -> URL {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    self.continuation = continuation
                    let task = resumeData.map { session.downloadTask(withResumeData: $0) }
                        ?? session.downloadTask(with: download.request)
                    self.task = task
                    task.resume()
                    // Cancelled before it started: the handler below has
                    // already run, so it's stopped here instead.
                    if Task.isCancelled {
                        task.cancel()
                    }
                }
            }
        } onCancel: {
            lock.withLock { task }?.cancel { _ in
                // The resume data also comes with the task's error, which
                // is where it's picked up.
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        guard fraction - reported >= 0.01 else { return }
        reported = fraction
        report(fraction)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The file is deleted once this returns, so it moves aside first.
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode
        guard status == 200 else {
            finished = .failure(Failure(status: status))
            return
        }
        let kept = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            finished = .success(kept)
        } catch {
            finished = .failure(Failure())
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let result: Result<URL, Failure>
        if let finished {
            result = finished
        } else if let error = error as? URLError {
            result = .failure(Failure(
                isCancellation: error.code == .cancelled,
                resumeData: error.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            ))
        } else {
            result = .failure(Failure())
        }
        lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }?.resume(with: result)
    }
}
