import SwiftData
import SwiftUI

/// Your reading status for every publication on a server you've opened,
/// looked up once for a whole screen rather than once per cell.
struct ReadingStatuses {
    private let byPublication: [Int64: ReadingStatus]

    init(_ states: [RemoteReadingState]) {
        byPublication = Dictionary(states.map { ($0.publicationID, $0.readingStatus) }, uniquingKeysWith: { first, _ in first })
    }

    subscript(publication: Int64) -> ReadingStatus {
        byPublication[publication] ?? .new
    }

    /// The status this device keeps, or `fallback` for a publication it
    /// hasn't opened, such as one read on another device.
    subscript(publication: Int64, or fallback: ReadingStatus?) -> ReadingStatus {
        byPublication[publication] ?? fallback ?? .new
    }
}

extension RemoteReadingState {
    static func onServer(_ server: UUID) -> Predicate<RemoteReadingState> {
        #Predicate { $0.serverID == server }
    }
}

extension ServerStore {
    /// `publication` ready for a cell or row.
    func item(_ publication: RemotePublication, status: ReadingStatus, showsSeries: Bool = true) -> PublicationItem {
        PublicationItem(publication, status: status, cover: cover(of: publication.id, on: publication.server), showsSeries: showsSeries)
    }
}

/// A quiet line at the top of a screen whose refresh failed while it still
/// shows what loaded earlier, so stale content never passes for fresh.
struct StaleNotice: View {
    let error: DisplayError

    var body: some View {
        Label(error.title, systemImage: "wifi.exclamationmark")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.margin)
            .transition(.opacity)
    }
}
