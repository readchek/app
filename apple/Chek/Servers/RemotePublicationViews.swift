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

/// A row that leads to another screen, lined up with the page margin and
/// separated by inset dividers, without a card around it.
struct NavigationRow<Value: Hashable>: View {
    let title: String
    let systemImage: String
    let value: Value
    var showsDivider = true

    var body: some View {
        VStack(spacing: 0) {
            NavigationLink(value: value) {
                HStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.body)
                        .foregroundStyle(.tint)
                        .frame(width: 28)
                    Text(title)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 12)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if showsDivider {
                Divider()
                    .padding(.leading, 40)
            }
        }
        .padding(.horizontal, Metrics.margin)
    }
}
