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
        let progress = DownloadProgress { [weak self] fraction in
            Task { @MainActor in
                guard let self, case .downloading = self.phase else { return }
                self.phase = .downloading(fraction)
            }
        }
        let (file, response) = try await URLSession.shared.download(for: download.request, delegate: progress)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            try? FileManager.default.removeItem(at: file)
            throw DisplayError(
                title: String(localized: "Couldn't download this publication."),
                message: String(localized: "Check your connection and try again.")
            )
        }
        try FileManager.default.createDirectory(at: download.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: download.destination)
        try FileManager.default.moveItem(at: file, to: download.destination)
        return download.destination
    }
}

/// Reports how much of a download has arrived, in steps of a percent so
/// the progress ring doesn't redraw for every packet.
private nonisolated final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let report: @Sendable (Double) -> Void
    // Only touched from the session's delegate queue, which is serial.
    private var reported = -1.0

    init(report: @escaping @Sendable (Double) -> Void) {
        self.report = report
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        guard fraction - reported >= 0.01 else { return }
        reported = fraction
        report(fraction)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The async download call moves the file; nothing to do here.
    }
}
