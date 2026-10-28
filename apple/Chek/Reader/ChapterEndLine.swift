import ChekReader
import SwiftUI

/// On the last page, one quiet line at the foot of the page saying what
/// comes next, which a tap opens. It reads like the running footer of a
/// book rather than a prompt, so it's there for anyone looking for the
/// way on and easy to read past for anyone who isn't. While the controls
/// show, their next button says the same, so the line steps aside.
struct ChapterEndLine: View {
    let session: ReaderSession
    /// What's being got ready to open, if anything.
    let opening: ReadingTarget?
    let open: (ReadingTarget) -> Void
    /// Asks again what comes next, after the server couldn't be reached.
    let retry: () -> Void
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        VStack {
            Spacer()
            if isShowing {
                line
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(foreground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(background, in: .capsule)
                    .transition(.opacity)
            }
        }
        // In the margin below the text, above the home indicator.
        .padding(.bottom, 24)
        .padding(.horizontal, Metrics.margin)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: isShowing)
    }

    private var isShowing: Bool {
        guard session.controller.state == .ready, session.isOnLastPage, !session.isShowingControls else { return false }
        switch session.next {
        case .found, .unknown, .end: return true
        case .looking, .none: return false
        }
    }

    @ViewBuilder private var line: some View {
        switch session.next {
        case .found(let target):
            Button {
                open(target)
            } label: {
                HStack(spacing: 4) {
                    Text("Next: \(target.title)")
                    if opening == target {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "chevron.forward")
                            .font(.caption2.weight(.bold))
                    }
                }
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(target.isChapter ? Text("Next Chapter") : Text("Next in Series"))
            .accessibilityValue(Text(target.title))
        case .unknown:
            // Offline, most likely: not the end, just not known.
            Button(action: retry) {
                HStack(spacing: 4) {
                    Text("Couldn't check what's next")
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2.weight(.bold))
                }
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Checks again."))
        case .end:
            session.item.sourceChapter == nil ? Text("End of the series") : Text("You're caught up")
        case .looking, .none:
            EmptyView()
        }
    }

    /// Over a comic's artwork, light text on a small shade so it reads
    /// whatever's drawn there. Under a book's text, the text's own color,
    /// dimmed, like a page number.
    private var foreground: Color {
        switch session.item.kind {
        case .comic: .white
        case .book: ReaderTheme(settings.theme).text.opacity(0.6)
        }
    }

    private var background: Color {
        switch session.item.kind {
        case .comic: .black.opacity(0.55)
        case .book: .clear
        }
    }
}
