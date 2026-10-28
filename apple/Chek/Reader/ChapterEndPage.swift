import ChekReader
import SwiftUI

/// Between one chapter and the next: what you've finished and what comes
/// after it, set as plain type on the page's own color, as Mihon's
/// chapter transition is. Comics show it after a turn past their last
/// page, so nothing sits on the artwork, and every chapter shows it while
/// the next one opens, in place of a blank screen.
///
/// Only the retry button takes touches. Swipes and taps go through to the
/// page underneath, so turning on again opens the next chapter and
/// turning back returns to the last page.
struct ChapterEndPage: View {
    let kind: PublicationKind
    /// The title of what you've just read, when it's still open.
    let finished: String?
    let next: NeighborLookup
    /// Whether ``next`` comes after, rather than before, what's open.
    var isNext = true
    let isOpening: Bool
    let retry: () -> Void
    @Environment(ReaderSettings.self) private var settings

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
                upNext
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
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var upNext: some View {
        switch next {
        case .found(let target):
            entry(isNext ? "Next" : "Previous", target.title)
                .allowsHitTesting(false)
        case .end, .caughtUp:
            Text(next == .end ? "That's the last one" : "You're caught up")
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

    @ViewBuilder private var footer: some View {
        if isOpening {
            ProgressView()
        } else if next.target != nil {
            Text("Turn the page to keep reading")
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
