import SwiftUI

/// Grey stand-ins the shape of what's loading, so a screen keeps its layout
/// while it waits and nothing jumps when the real thing arrives. They
/// shimmer, as placeholders do across the system, unless Reduce Motion is on.

extension View {
    /// A soft highlight sweeping across the view, to say it's loading.
    func shimmering() -> some View {
        modifier(Shimmer())
    }
}

private struct ShimmerIf: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.shimmering()
        } else {
            content.accessibilityHidden(true)
        }
    }
}

private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        LinearGradient(colors: [.clear, .primary.opacity(0.08), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: width * 0.6)
                            .offset(x: -width * 0.6 + phase * width * 1.6)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Loading"))
    }
}

/// A bar standing in for a line of text.
private struct TextBar: View {
    var width: CGFloat?
    var height: CGFloat = 10

    var body: some View {
        Capsule()
            .fill(.fill.tertiary)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// A cover and its caption, before either has loaded.
struct PlaceholderCoverCell: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.captionSpacing) {
            RoundedRectangle(cornerRadius: 6)
                .fill(.fill.tertiary)
                .aspectRatio(2 / 3, contentMode: .fit)
            VStack(alignment: .leading, spacing: 5) {
                TextBar()
                TextBar(width: 48, height: 8)
            }
        }
    }
}

/// A shelf's worth of covers, laid out as a shelf is.
struct PlaceholderShelf: View {
    /// Off for a shelf that's empty rather than loading.
    var isLoading = true

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Metrics.coverSpacing) {
                ForEach(0..<6, id: \.self) { _ in
                    PlaceholderCoverCell()
                        .shelfCell()
                }
            }
        }
        .contentMargins(.horizontal, Metrics.margin, for: .scrollContent)
        .scrollDisabled(true)
        .scrollIndicators(.hidden)
        .modifier(ShimmerIf(isOn: isLoading))
    }
}

/// A screenful of a cover grid.
struct PlaceholderGrid: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        LazyVGrid(columns: Metrics.gridColumns(regular: sizeClass == .regular), spacing: Metrics.gridRowSpacing) {
            ForEach(0..<12, id: \.self) { _ in
                PlaceholderCoverCell()
            }
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.vertical, 8)
        .shimmering()
    }
}

/// A row with a small cover, as search results and lists show books.
struct PlaceholderRow: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: Metrics.rowCoverRadius)
                .fill(.fill.tertiary)
                .frame(width: Metrics.rowCoverWidth, height: Metrics.rowCoverWidth * 1.5)
            VStack(alignment: .leading, spacing: 6) {
                TextBar(width: 180, height: 12)
                TextBar(width: 110, height: 9)
            }
            Spacer(minLength: 0)
        }
        .shimmering()
    }
}

/// A chapter's row: its title and date, before the list has loaded.
struct PlaceholderChapterRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextBar(width: 150, height: 12)
            TextBar(width: 80, height: 9)
        }
        .padding(.vertical, 6)
        .shimmering()
    }
}
