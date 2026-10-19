import SwiftData
import SwiftUI

/// A server publication's cover with its title and your place in it.
/// Tapping it opens the reader.
struct RemotePublicationTile: View {
    let publication: RemotePublication
    let status: ReadingStatus
    var width: CGFloat?
    @Environment(AppRouter.self) private var router
    @Environment(ServerStore.self) private var servers
    @Environment(ServerSync.self) private var sync

    var body: some View {
        Button {
            router.open(publication, using: sync)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                CoverView(source: servers.cover(of: publication.id, on: publication.server), title: publication.title)
                    .overlay {
                        OpeningIndicator(ref: publication.ref)
                    }
                    .readerTransitionSource(publication.ref)
                VStack(alignment: .leading, spacing: 2) {
                    Text(publication.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    ReadingStatusLabel(status: status)
                }
            }
            .frame(width: width)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!publication.isAvailable)
        .accessibilityElement(children: .combine)
    }
}

/// A server publication as a row, for series and search results.
struct RemotePublicationRow: View {
    let publication: RemotePublication
    let status: ReadingStatus
    /// Off in a series' own list, where every row has the same series.
    var showsSeries = true
    @Environment(AppRouter.self) private var router
    @Environment(ServerStore.self) private var servers
    @Environment(ServerSync.self) private var sync

    var body: some View {
        Button {
            router.open(publication, using: sync)
        } label: {
            HStack(spacing: 14) {
                CoverView(source: servers.cover(of: publication.id, on: publication.server), title: publication.title, cornerRadius: 4)
                    .frame(width: 48)
                    .overlay {
                        OpeningIndicator(ref: publication.ref)
                    }
                    .readerTransitionSource(publication.ref)
                VStack(alignment: .leading, spacing: 3) {
                    Text(publication.displayTitle)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                    if showsSeries, let series = publication.seriesTitle, series != publication.title {
                        Text(series)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        ReadingStatusLabel(status: status)
                        Text(publication.format.uppercased())
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// A spinner over the cover while the publication gets ready to open.
private struct OpeningIndicator: View {
    let ref: PublicationRef
    @Environment(AppRouter.self) private var router

    var body: some View {
        if router.opening == ref {
            ProgressView()
                .padding(10)
                .glassEffect(.regular, in: .circle)
        }
    }
}

/// Your reading status for every publication on a server you've opened,
/// looked up once for a whole screen rather than once per tile.
struct ReadingStatuses {
    private let byPublication: [Int64: ReadingStatus]

    init(_ states: [RemoteReadingState]) {
        byPublication = Dictionary(states.map { ($0.publicationID, $0.readingStatus) }, uniquingKeysWith: { first, _ in first })
    }

    subscript(publication: Int64) -> ReadingStatus {
        byPublication[publication] ?? .new
    }
}

extension RemoteReadingState {
    static func onServer(_ server: UUID) -> Predicate<RemoteReadingState> {
        #Predicate { $0.serverID == server }
    }
}
