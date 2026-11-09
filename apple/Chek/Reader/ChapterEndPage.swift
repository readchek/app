import ChekReader
import SwiftUI

/// Between one chapter and the next: the chapter it leads to, in plain
/// type on the page's own color. One turn past the last page shows the
/// next chapter, and one back past the first shows the one before.
///
/// In the reader it's a page among the chapter's, turned or scrolled onto
/// and away from as they are, and going on past it opens the chapter it
/// names. In a PDF, which has no room for it, it covers the pages and
/// turns the same way by itself.
struct ChapterEndPage: View {
    let kind: PublicationKind
    let next: NeighborLookup
    /// Whether ``next`` comes after, rather than before, what's open.
    var isNext = true
    let isOpening: Bool
    let retry: () -> Void
    /// Readers' comments on what you've finished, when it has some.
    var comments: ChapterComments?
    /// Opens the comments.
    var showComments: () -> Void = {}
    /// Which way the pages around it turn.
    var turns: Turns = .leftToRight
    /// Whether it turns by itself for a swipe, rather than as one of the
    /// reader's pages, whose own swipe turns it.
    var followsSwipes = true
    /// Turns the page, forward or back. Nil while the next chapter opens,
    /// when there's nothing to turn to.
    var turn: ((_ forward: Bool) -> Void)?
    /// Shows or hides the reader's controls, for a tap in the middle.
    var tapMiddle: () -> Void = {}
    @Environment(ReaderSettings.self) private var settings

    /// The side a page turn forward goes toward.
    enum Turns {
        case leftToRight, rightToLeft
    }

    var body: some View {
        ZStack {
            canvas
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 16) {
                upNext
                commentsLine
            }
            .frame(maxWidth: 340, alignment: .leading)
            .padding(.horizontal, 32)
            // A little above the middle, where the eye takes the middle to be.
            .padding(.bottom, 80)
        }
        .overlay(alignment: .bottom) {
            if isOpening {
                OpeningSpinner()
                    .padding(.bottom, 48)
            }
        }
        .foregroundStyle(primary)
        .contentShape(.rect)
        .modifier(PageTurning(turns: turns, followsSwipes: followsSwipes, turn: turn, tapMiddle: tapMiddle))
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: isNext ? Text("Next Chapter") : Text("Previous Chapter")) {
            turn?(isNext)
        }
    }

    @ViewBuilder private var upNext: some View {
        switch next {
        case .found(let target):
            VStack(alignment: .leading, spacing: 4) {
                Text(isNext ? "Next" : "Previous")
                    .font(.subheadline)
                    .foregroundStyle(secondary)
                Text(target.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(3)
            }
            .accessibilityElement(children: .combine)
            .allowsHitTesting(false)
        case .end, .caughtUp:
            (next == .end ? Text("That's the last one") : Text("You're caught up"))
                .font(.subheadline)
                .foregroundStyle(secondary)
                .allowsHitTesting(false)
        case .unknown:
            // Offline, most likely: not the end, just not known.
            Button(action: retry) {
                Label("Couldn't check what's next", systemImage: "arrow.clockwise")
                    .font(.subheadline)
                    .foregroundStyle(secondary)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Checks again."))
        case .looking:
            ProgressView()
                .allowsHitTesting(false)
        case .none:
            EmptyView()
        }
    }

    /// How many comments the chapter has, as a quiet link to them, or to
    /// the thread on the site when that's all it gives. Only at the end,
    /// where the chapter they're about has just been read.
    @ViewBuilder private var commentsLine: some View {
        if isNext, let comments, let count = comments.count, count > 0 {
            let label = Label {
                Text("^[\(count) comment](inflect: true)")
            } icon: {
                Image(systemName: "bubble")
            }
            .font(.subheadline)
            .foregroundStyle(secondary)
            if comments.hasList {
                Button(action: showComments) { label }
                    .buttonStyle(.plain)
            } else if let thread = comments.thread {
                Link(destination: thread) { label }
                    .buttonStyle(.plain)
            }
        }
    }

    private var canvas: Color {
        switch kind {
        case .comic: .black
        case .book: ReaderTheme(settings.theme).background
        }
    }

    private var primary: Color {
        switch kind {
        case .comic: .white
        case .book: ReaderTheme(settings.theme).text
        }
    }

    private var secondary: Color {
        primary.opacity(0.6)
    }
}

/// Shows once the next chapter has been waited on a moment. It's usually
/// fetched ahead, and a spinner that flashes for an instant is noise.
private struct OpeningSpinner: View {
    @State private var isShowing = false

    var body: some View {
        ProgressView()
            .opacity(isShowing ? 1 : 0)
            .task {
                try? await Task.sleep(for: .milliseconds(600))
                isShowing = true
            }
    }
}

/// Turns the chapter's end as its pages turn: a tap at either side and,
/// when it turns by itself, a swipe across or a swipe up and down as a
/// scrolled comic moves. A tap in the middle is for the reader's controls.
private struct PageTurning: ViewModifier {
    let turns: ChapterEndPage.Turns
    let followsSwipes: Bool
    let turn: ((_ forward: Bool) -> Void)?
    let tapMiddle: () -> Void
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onTapGesture { point in
                guard width > 0 else { return }
                let place = point.x / width
                guard place < 0.3 || place > 0.7 else {
                    tapMiddle()
                    return
                }
                // The trailing side is the way on, as it is on the pages.
                turn?((place > 0.7) == (turns == .leftToRight))
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        let across = value.translation.width
                        let down = value.translation.height
                        if abs(across) > abs(down) * 1.5, abs(across) > 40 {
                            // The next page comes in from the trailing side.
                            turn?((across < 0) == (turns == .leftToRight))
                        } else if abs(down) > abs(across) * 1.5, abs(down) > 60, value.startLocation.y > 140 {
                            // Scrolling on is pushing the page up. From the
                            // top edge a pull down closes the reader instead.
                            turn?(down < 0)
                        }
                    },
                isEnabled: followsSwipes
            )
    }
}
