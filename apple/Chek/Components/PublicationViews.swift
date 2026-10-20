import SwiftUI

/// Spacing shared by every screen, so edges and gaps line up across the app.
enum Metrics {
    /// The leading and trailing margin of scrolling content.
    static let margin: CGFloat = 20
    /// Between covers in grids and shelves.
    static let coverSpacing: CGFloat = 16
    /// Between rows of covers in a grid.
    static let gridRowSpacing: CGFloat = 20
    /// Between sections on a page.
    static let sectionSpacing: CGFloat = 32
    /// A cover's width in a shelf, larger on iPad's wider screen.
    static func shelfCoverWidth(regular: Bool) -> CGFloat {
        regular ? 140 : 108
    }
    /// A cover's width in the Continue Reading carousel.
    static func featuredCoverWidth(regular: Bool) -> CGFloat {
        regular ? 200 : 150
    }
    /// A cover's width in a list row.
    static let rowCoverWidth: CGFloat = 44

    /// Three covers across on iPhone, as in Panels, and covers about as
    /// large as Books' on iPad.
    static func gridColumns(regular: Bool) -> [GridItem] {
        regular
            ? [GridItem(.adaptive(minimum: 140, maximum: 190), spacing: 20, alignment: .top)]
            : [GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 12, alignment: .top)]
    }
}

/// A cover with a one-line title and a small status under it, as in Panels.
/// Used in every grid and shelf.
struct PublicationCell: View {
    let item: PublicationItem

    var body: some View {
        OpenPublicationButton(item: item) {
            VStack(alignment: .leading, spacing: 6) {
                CoverView(source: item.cover, title: item.title)
                    .overlay {
                        OpeningIndicator(ref: item.id)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        ItemDownloadIndicator(item: item, onCover: true)
                    }
                    .readerTransitionSource(item.id)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    if case .chapter = item.source, let chapter = item.subtitle {
                        // A source chapter's cell is its series, so which
                        // chapter you're on goes with how far you are.
                        HStack(spacing: 3) {
                            Text(chapter)
                                .foregroundStyle(.secondary)
                                .layoutPriority(-1)
                            if item.status != .started {
                                Text(verbatim: "·")
                                    .foregroundStyle(.tertiary)
                                StatusText(status: item.status, fallback: nil, font: .caption2)
                            }
                        }
                        .font(.caption2)
                        .lineLimit(1)
                    } else {
                        StatusText(status: item.status, fallback: nil, font: .caption2)
                    }
                }
            }
            .contentShape(.rect)
        }
        .comicDownloadMenu(for: item)
        .accessibilityElement(children: .combine)
    }
}

/// A small cover with title, subtitle and status. Used in every list.
struct PublicationRow: View {
    let item: PublicationItem

    var body: some View {
        OpenPublicationButton(item: item) {
            HStack(spacing: 12) {
                CoverView(source: item.cover, title: item.title)
                    .frame(width: Metrics.rowCoverWidth)
                    .overlay {
                        OpeningIndicator(ref: item.id)
                    }
                    .readerTransitionSource(item.id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body)
                        .lineLimit(2)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                StatusText(status: item.status, fallback: nil)
                ItemDownloadIndicator(item: item)
            }
            .contentShape(.rect)
        }
        .comicDownloadMenu(for: item)
        .accessibilityElement(children: .combine)
    }
}

/// Where you are, in a few words of caption text: "New", "34%" or
/// "Finished". Shows `fallback` when there's nothing to say yet.
struct StatusText: View {
    let status: ReadingStatus
    let fallback: String?
    var font: Font = .caption

    var body: some View {
        Group {
            switch status {
            case .new:
                Text("New")
                    .foregroundStyle(.tint)
            case .started:
                Text("Started")
                    .foregroundStyle(.secondary)
            case .inProgress(let progress) where progress < 0.01:
                Text("Started")
                    .foregroundStyle(.secondary)
            case .inProgress(let progress):
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            case .finished:
                Text("Finished")
                    .foregroundStyle(.secondary)
            }
        }
        .font(font)
        .lineLimit(1)
    }
}

/// A section title, which leads to the whole list when it has somewhere to
/// go, as section titles do in Books and Music.
struct SectionHeader<Destination: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var destination: Destination

    var body: some View {
        Group {
            if Destination.self == EmptyView.self {
                label
            } else {
                NavigationLink {
                    destination
                } label: {
                    HStack(spacing: 4) {
                        label
                        Image(systemName: "chevron.forward")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.margin)
    }

    private var label: some View {
        Text(title)
            .font(.title3.weight(.bold))
            .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Destination == EmptyView {
    init(title: LocalizedStringKey) {
        self.title = title
        destination = EmptyView()
    }
}

/// A titled row of covers that scrolls sideways.
struct Shelf: View {
    let title: LocalizedStringKey
    let items: [PublicationItem]
    /// Larger covers with titles, for what you're reading.
    var isFeatured = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let regular = sizeClass == .regular
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .bottom, spacing: isFeatured ? 20 : Metrics.coverSpacing) {
                    ForEach(items) { item in
                        PublicationCell(item: item)
                            .frame(width: isFeatured ? Metrics.featuredCoverWidth(regular: regular) : Metrics.shelfCoverWidth(regular: regular))
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, Metrics.margin, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }
}

/// A spinner over a cover while its publication gets ready to open.
private struct OpeningIndicator: View {
    let ref: PublicationRef
    @Environment(AppRouter.self) private var router

    var body: some View {
        if router.opening == ref {
            ZStack {
                Color.black.opacity(0.35)
                ProgressView()
                    .tint(.white)
            }
        }
    }
}

/// Whether a series screen's header, which shows its title large, is on
/// screen, so the bar can leave the title out until it isn't.
struct SeriesHeaderVisibleKey: PreferenceKey {
    static let defaultValue = true

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value && nextValue()
    }
}
