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
    static let shelfCoverWidth: CGFloat = 116
    /// A cover's width in a list row.
    static let rowCoverWidth: CGFloat = 44

    /// Three covers across on iPhone, more on wider screens.
    static let gridColumns = [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: coverSpacing, alignment: .top)]
}

/// A cover with its title and one line under it. Used in every grid and
/// shelf.
struct PublicationCell: View {
    let item: PublicationItem
    /// Continue Reading shows a progress bar; everywhere else uses text.
    var showsProgressBar = false

    var body: some View {
        OpenPublicationButton(item: item) {
            VStack(alignment: .leading, spacing: 6) {
                CoverView(source: item.cover, title: item.title)
                    .overlay {
                        OpeningIndicator(ref: item.id)
                    }
                    .readerTransitionSource(item.id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.footnote.weight(.medium))
                        .lineLimit(2, reservesSpace: true)
                    if showsProgressBar, let progress = item.status.progress {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .padding(.top, 4)
                    } else {
                        StatusText(status: item.status, fallback: item.subtitle)
                    }
                }
            }
            .contentShape(.rect)
        }
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

/// A section title with an optional "See All" link, aligned to the margin.
struct SectionHeader<Destination: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var destination: Destination

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if Destination.self != EmptyView.self {
                NavigationLink("See All") {
                    destination
                }
                .font(.subheadline)
            }
        }
        .padding(.horizontal, Metrics.margin)
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
    var showsProgressBar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Metrics.coverSpacing) {
                    ForEach(items) { item in
                        PublicationCell(item: item, showsProgressBar: showsProgressBar)
                            .frame(width: Metrics.shelfCoverWidth)
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
