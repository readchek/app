import Foundation

/// A publication on a server, with what the app needs to show and open it.
/// Made from the server's listing, or from your saved place when offline.
nonisolated struct RemotePublication: Identifiable, Hashable, Codable, Sendable {
    let server: UUID
    let id: Int64
    let title: String
    let seriesID: Int64?
    let seriesTitle: String?
    let numberLabel: String?
    let format: String
    let pageCount: Int?
    let hasCover: Bool
    /// False when the file is missing from the server's disk. The server
    /// keeps it listed so your place survives, but it can't be opened.
    let isAvailable: Bool

    var ref: PublicationRef { .server(server, id) }
    var kind: PublicationKind { PublicationKind(serverFormat: format) }

    /// "Vol. 3" or "3", with the title when it says more than the number.
    var displayTitle: String {
        // Files without metadata are titled by their file name on the
        // server, such as "peppercarrot_episode01".
        let title = title.contains(" ") ? title : BookImporter.title(fromFileName: title)
        guard let numberLabel, !numberLabel.isEmpty else { return title }
        return title.localizedCaseInsensitiveContains(numberLabel) ? title : "\(numberLabel) · \(title)"
    }

    init(_ summary: ChekAPI.PublicationSummary, server: UUID) {
        self.server = server
        id = summary.id
        title = summary.title
        seriesID = summary.series.id
        seriesTitle = summary.series.title
        numberLabel = summary.numberLabel
        format = summary.format
        pageCount = summary.pageCount
        hasCover = summary.hasCover
        isAvailable = summary.available
    }

    init(_ state: RemoteReadingState) {
        server = state.serverID
        id = state.publicationID
        title = state.title
        seriesID = state.seriesID
        seriesTitle = state.seriesTitle
        numberLabel = state.numberLabel
        format = state.format
        pageCount = nil
        hasCover = state.hasCover
        isAvailable = true
    }
}
