import SwiftUI

/// Spacing shared by every screen, so edges and gaps line up across the app.
enum Metrics {
    /// The leading and trailing margin of scrolling content.
    static let margin: CGFloat = 20
    /// Between covers in grids and shelves.
    static let coverSpacing: CGFloat = 16
    /// Between rows of covers in a grid.
    static let gridRowSpacing: CGFloat = 24
    /// Between sections on a page.
    static let sectionSpacing: CGFloat = 32
    /// A cover's width in a shelf.
    static let shelfCoverWidth: CGFloat = 112
    /// A cover's width in the Continue Reading carousel.
    static let featuredCoverWidth: CGFloat = 172
    /// A cover's width in a list row.
    static let rowCoverWidth: CGFloat = 44

    /// Two covers across on iPhone, as in Books, more on wider screens.
    static let gridColumns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 24, alignment: .bottom)]
}

/// A cover with one quiet line under it. The cover carries the title, as
/// on a shelf; VoiceOver reads it. Used in every grid and shelf.
struct PublicationCell: View {
    let item: PublicationItem
    /// Shows the title under the cover too, for the larger Continue Reading
    /// covers where a glance should be enough.
    var showsTitle = false

    var body: some View {
        OpenPublicationButton(item: item) {
            VStack(alignment: .leading, spacing: 8) {
                CoverView(source: item.cover, title: item.title)
                    .overlay {
                        OpeningIndicator(ref: item.id)
                    }
                    .readerTransitionSource(item.id)
                VStack(alignment: .leading, spacing: 1) {
                    if showsTitle {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    StatusText(status: item.status, fallback: nil)
                }
            }
            .contentShape(.rect)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(item.title))
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
            }
            .contentShape(.rect)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Where you are, in a few words of caption text: "New", "34%" or
/// "Finished". Shows `fallback` when there's nothing to say yet.
struct StatusText: View {
    let status: ReadingStatus
    let fallback: String?

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
        .font(.caption)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .bottom, spacing: isFeatured ? 20 : Metrics.coverSpacing) {
                    ForEach(items) { item in
                        PublicationCell(item: item, showsTitle: isFeatured)
                            .frame(width: isFeatured ? Metrics.featuredCoverWidth : Metrics.shelfCoverWidth)
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
