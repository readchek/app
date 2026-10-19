import Foundation

/// Identifies anything Chek can open, wherever it lives.
///
/// Routes, zoom transitions, reading positions and caches are all keyed by
/// it, so the same publication is the same thing everywhere in the app.
nonisolated enum PublicationRef: Hashable, Codable, Sendable {
    /// A book in the on-device library.
    case local(UUID)
    /// A publication on a connected server.
    case server(UUID, Int64)
    /// A chapter read straight from one of a server's sources: the server,
    /// the extension's id and the source's own chapter id.
    case source(UUID, String, String)

    /// A stable string form, for unique keys in storage.
    var storageKey: String {
        switch self {
        case .local(let id): "local/\(id.uuidString)"
        case .server(let server, let publication): "server/\(server.uuidString)/\(publication)"
        case .source(let server, let source, let chapter): "source/\(server.uuidString)/\(source)/\(chapter)"
        }
    }
}

/// Whether a publication reads like a book or like a comic, which decides
/// how it's shown and which reading settings apply.
nonisolated enum PublicationKind: String, Codable, Sendable, CaseIterable {
    case book
    case comic

    init(serverFormat: String) {
        switch serverFormat {
        case "cbz", "cbt", "cbr", "cb7", "remote": self = .comic
        default: self = .book
        }
    }
}

/// How far along you are in a publication, worked out once for every
/// place that shows it.
nonisolated enum ReadingStatus: Hashable, Sendable {
    case new
    case started
    case inProgress(Double)
    case finished

    /// Progress at or past this counts as finished, since the last page of
    /// a book rarely reports exactly 1.
    static let finishedThreshold = 0.995

    init(progress: Double?, finished: Bool, opened: Bool) {
        if finished {
            self = .finished
        } else if let progress, progress > 0 {
            self = .inProgress(min(progress, 1))
        } else {
            self = opened ? .started : .new
        }
    }

    var progress: Double? {
        switch self {
        case .new: nil
        case .started: 0
        case .inProgress(let value): value
        case .finished: 1
        }
    }
}
