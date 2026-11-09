import ChekReader
import SwiftUI

/// Between one chapter and the next: what you've finished and what comes
/// after it, set as plain type on the page's own color, as Mihon's
/// chapter transition is. Every book and comic shows it one turn past its
/// last page, so nothing sits on the artwork, and one turn back past its
/// first page shows the chapter before the same way. It also shows while
/// the next one opens, in place of a blank screen.
///
/// It's a page like any other: a tap at the side or a swipe turns it.
/// Turning on from the end opens the next chapter and turning back
/// returns to the last page, which stays put underneath.
struct ChapterEndPage: View {
    let kind: PublicationKind
    /// The title of what you've just read, when it's still open.
    let finished: String?
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
            VStack(alignment: .leading, spacing: 32) {
                if let finished {
                    entry("Finished", finished)
                        .allowsHitTesting(false)
                }
                VStack(alignment: .leading, spacing: 16) {
                    upNext
                    commentsLine
                }
            }
            .frame(maxWidth: 340, alignment: .leading)
            .padding(.horizontal, 32)
            // A little above the middle, where the eye takes the middle to be.
            .padding(.bottom, 80)
        }
        .overlay(alignment: .bottom) {
            footer
                .padding(.bottom, 48)
                .allowsHitTesting(false)
        }
        .foregroundStyle(primary)
        .contentShape(.rect)
        .modifier(PageTurning(turns: turns, turn: turn, tapMiddle: tapMiddle))
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: isNext ? Text("Next Chapter") : Text("Previous Chapter")) {
            turn?(isNext)
        }
    }

    @ViewBuilder private var upNext: some View {
        switch next {
        case .found(let target):
            entry(isNext ? "Next" : "Previous", target.title)
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
    /// the thread on the site when that's all it gives.
    @ViewBuilder private var commentsLine: some View {
        if let comments, let count = comments.count {
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

    @ViewBuilder private var footer: some View {
        if isOpening {
            ProgressView()
        } else if next.target != nil {
            (isNext ? Text("Turn the page to keep reading") : Text("Turn back again to open it"))
                .font(.footnote)
                .foregroundStyle(secondary)
        }
    }

    private func entry(_ label: LocalizedStringKey, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(secondary)
            Text(title)
                .font(.title3.weight(.semibold))
                .lineLimit(3)
        }
        .accessibilityElement(children: .combine)
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

/// Turns the chapter's end as its pages turn: a tap at either side, a
/// swipe across, or a swipe up and down as a scrolled comic moves. A tap
/// in the middle is for the reader's controls.
private struct PageTurning: ViewModifier {
    let turns: ChapterEndPage.Turns
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
                    }
            )
    }
}
