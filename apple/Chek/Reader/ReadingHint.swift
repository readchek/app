import ChekReader
import SwiftUI

/// Shown once, the first time the reader opens: where to tap to turn
/// pages and to show the controls, since nothing else says so.
struct ReadingHint: View {
    let session: ReaderSession
    @AppStorage("reader.hasShownHint") private var hasShown = false
    @State private var isVisible = false
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        ZStack {
            if isVisible {
                // A light dim and one sentence, as Panels does: dashed
                // tap zones drawn over the page were more than it needs.
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .overlay(alignment: .bottom) {
                        // On its own panel: the dimmed page's text still
                        // shows through, and white on it isn't readable.
                        Text(isScrolled ? "Scroll to read. Tap the middle for controls." : "Tap the sides or swipe to turn. Tap the middle for controls.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.black.opacity(0.7), in: .rect(cornerRadius: 14))
                            .padding(.horizontal, 32)
                            .padding(.bottom, 120)
                    }
                    .onTapGesture { dismiss() }
                    .transition(.opacity)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(Text("Reading tips. Double-tap to dismiss."))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isVisible)
        .task {
            guard !hasShown else { return }
            // After the page is there, so the hint explains what's on screen.
            try? await Task.sleep(for: .seconds(1))
            // The controls would sit over the hint.
            session.hideControls()
            isVisible = true
        }
    }

    /// Whether the pages scroll down in one column, where there's no
    /// page to turn.
    private var isScrolled: Bool {
        session.item.kind == .comic && settings.preferences(for: session.item.settingsKey).comicFlow == .scrolled
    }

    private func dismiss() {
        hasShown = true
        isVisible = false
    }
}
