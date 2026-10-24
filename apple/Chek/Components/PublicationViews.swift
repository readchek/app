import SwiftUI

/// Spacing shared by every screen, so edges and gaps line up across the app.
enum Metrics {
    /// The leading and trailing margin of scrolling content. The same as a
    /// list row's inset, so rows, shelves and grids share one left edge.
    static let margin: CGFloat = 20
    /// Between covers, in shelves and grids alike.
    static let coverSpacing: CGFloat = 12
    /// Between rows of covers in a grid.
    static let gridRowSpacing: CGFloat = 20
    /// Between shelves on a page.
    static let sectionSpacing: CGFloat = 28
    /// From a cover to the caption under it.
    static let captionSpacing: CGFloat = 6
    /// A cover's width in the Continue Reading carousel.
    static func featuredCoverWidth(regular: Bool) -> CGFloat {
        regular ? 200 : 150
    }
    /// A cover's width in a list row, and its corners, tighter than a big
    /// cover's so a small one doesn't look like a pill.
    static let rowCoverWidth: CGFloat = 44
    static let rowCoverRadius: CGFloat = 4
    /// The cover in a series header.
    static func headerCoverWidth(regular: Bool) -> CGFloat {
        regular ? 140 : 110
    }
    /// How many covers a shelf shows across, the same as the grid so a
    /// cover is one size on both.
    static func shelfColumns(regular: Bool) -> Int {
        regular ? 5 : 3
    }

    /// Three covers across on iPhone, as in Panels, and covers about as
    /// large as Books' on iPad.
    static func gridColumns(regular: Bool) -> [GridItem] {
        regular
            ? [GridItem(.adaptive(minimum: 140, maximum: 190), spacing: coverSpacing, alignment: .top)]
            : [GridItem(.adaptive(minimum: 100, maximum: 150), spacing: coverSpacing, alignment: .top)]
    }
}

extension View {
    /// Sizes a shelf cell like a grid cell, so shelves and grids line up.
    func shelfCell(featured: Bool = false) -> some View {
        modifier(ShelfCell(isFeatured: featured))
    }

    /// A shelf as a row of a list page: edge to edge, with no separator.
    /// With a header row's top inset, shelves sit `sectionSpacing` apart.
    func shelfRow() -> some View {
        listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: Metrics.sectionSpacing - 12, trailing: 0))
            .listRowSeparator(.hidden)
    }

    /// A section header as a row of a list page, above ordinary rows.
    func headerRow() -> some View {
        listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 4, trailing: 0))
            .listRowSeparator(.hidden)
    }
}

private struct ShelfCell: ViewModifier {
    let isFeatured: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        let regular = sizeClass == .regular
        if isFeatured {
            content.frame(width: Metrics.featuredCoverWidth(regular: regular))
        } else {
            // Measured from the shelf's own width, less its margins, so the
            // cells are exactly the grid's on any screen.
            content.containerRelativeFrame(.horizontal, count: Metrics.shelfColumns(regular: regular), spacing: Metrics.coverSpacing)
        }
    }
}

/// The words under a cover: a title and, in smaller secondary type, the
/// one detail that matters there (author, series, chapter, count, or how
/// far you are). Every grid and shelf uses it, so captions match.
struct CoverCaption: View {
    let title: String
    var detail: Text?
    /// For a detail that wants attention, such as a count of new chapters.
    var isDetailHighlighted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote)
                .lineLimit(2)
            if let detail {
                detail
                    .font(.caption)
                    .foregroundStyle(isDetailHighlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A cover with its caption, as in Books and Panels. Used in every grid
/// and shelf.
struct PublicationCell: View {
    let item: PublicationItem
    /// Whether the cell is wide enough for the subtitle and the status
    /// together, as Continue Reading's are.
    var isFeatured = false

    var body: some View {
        OpenPublicationButton(item: item) {
            VStack(alignment: .leading, spacing: Metrics.captionSpacing) {
                CoverView(source: item.cover, title: item.title)
                    .overlay {
                        OpeningIndicator(ref: item.id)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        ItemDownloadIndicator(item: item, onCover: true)
                    }
                    .readerTransitionSource(item.id)
                CoverCaption(title: item.title, detail: detail)
            }
            .contentShape(.rect)
        }
        .comicDownloadMenu(for: item)
        .accessibilityElement(children: .combine)
    }

    /// How far you are once you've started, or else the author, series or
    /// chapter: one line, since both together won't fit under a grid
    /// cover; a featured cover has room for "Berserk · 42%". An unopened
    /// item has no status: "New" under every cover means nothing.
    private var detail: Text? {
        if case .chapter = item.source, let chapter = item.subtitle {
            // A source chapter's cell is its series, so which chapter
            // you're on is the one thing worth saying.
            return Text(chapter)
        }
        if isFeatured {
            let parts = [item.subtitle, item.status.caption].compactMap(\.self)
            return parts.isEmpty ? nil : Text(parts.joined(separator: " · "))
        }
        return (item.status.caption ?? item.subtitle).map { Text($0) }
    }
}

/// A small cover with title, subtitle and status. Used in every list.
struct PublicationRow: View {
    let item: PublicationItem

    var body: some View {
        OpenPublicationButton(item: item) {
            HStack(spacing: 12) {
                CoverView(source: item.cover, title: item.title, cornerRadius: Metrics.rowCoverRadius)
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
                StatusText(status: item.status)
                ItemDownloadIndicator(item: item)
            }
            .contentShape(.rect)
        }
        .comicDownloadMenu(for: item)
        .accessibilityElement(children: .combine)
    }
}

extension ReadingStatus {
    /// Where you are, in a word or two: "Started", "34%" or "Finished".
    /// Nothing for something unopened, since most things are.
    var caption: String? {
        switch self {
        case .new:
            nil
        case .started:
            String(localized: "Started")
        case .inProgress(let progress) where progress < 0.01:
            String(localized: "Started")
        case .inProgress(let progress):
            progress.formatted(.percent.precision(.fractionLength(0)))
        case .finished:
            String(localized: "Finished")
        }
    }
}

/// A reading status as secondary caption text, for the trailing end of a
/// row.
struct StatusText: View {
    let status: ReadingStatus
    var font: Font = .caption

    var body: some View {
        if let caption = status.caption {
            Text(caption)
                .font(font)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// A section title, which leads to the whole list when it has somewhere to
/// go, as section titles do in Books and Music.
struct SectionHeader: View {
    let title: LocalizedStringKey
    /// Where the title leads, if anywhere.
    var route: Route?
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            if let route {
                // A button through the router, not a `NavigationLink`: in a
                // list row a link gets the cell's own chevron at the trailing
                // edge, a second arrow pointing at nothing.
                Button {
                    router.push(route)
                } label: {
                    HStack(spacing: 6) {
                        label
                        // Smaller than the title and quieter, as Music draws it.
                        Image(systemName: "chevron.forward")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                label
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.margin)
    }

    private var label: some View {
        Text(title)
            .font(.title2.weight(.bold))
            .accessibilityAddTraits(.isHeader)
    }
}

/// A titled row of anything that scrolls sideways, snapping to its cells.
/// Every shelf is one of these, so they all share one header and one
/// scroll behavior.
struct CoverShelf<Content: View>: View {
    let title: LocalizedStringKey
    /// Where the header leads, if anywhere.
    var route: Route?
    /// Larger covers with more room between them, for what you're reading.
    var isFeatured = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, route: route)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: isFeatured ? 16 : Metrics.coverSpacing) {
                    content
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

/// A shelf of publications.
struct Shelf: View {
    let title: LocalizedStringKey
    let items: [PublicationItem]
    var route: Route?
    var isFeatured = false
    @State private var bookToRemove: Book?

    var body: some View {
        CoverShelf(title: title, route: route, isFeatured: isFeatured) {
            ForEach(items) { item in
                PublicationCell(item: item, isFeatured: isFeatured)
                    .shelfCell(featured: isFeatured)
                    // The same menu as in Library, so a book can be
                    // finished, shared or removed where you see it.
                    .contextMenu {
                        if case .local(let book) = item.source {
                            BookActions(book: book, bookToRemove: $bookToRemove)
                        }
                    }
            }
        }
        .removeBookConfirmation(book: $bookToRemove)
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
