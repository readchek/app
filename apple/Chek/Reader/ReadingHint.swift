import SwiftUI

/// Shown once, the first time the reader opens: where to tap to turn
/// pages and to show the controls, since nothing else says so.
struct ReadingHint: View {
    let session: ReaderSession
    @AppStorage("reader.hasShownHint") private var hasShown = false
    @State private var isVisible = false

    var body: some View {
        ZStack {
            if isVisible {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .overlay {
                        HStack(spacing: 0) {
                            zone("Previous", systemImage: "chevron.backward")
                            zone("Controls", systemImage: "hand.tap")
                            zone("Next", systemImage: "chevron.forward")
                        }
                        .padding(.horizontal, 12)
                    }
                    .overlay(alignment: .bottom) {
                        // On its own panel: the dimmed page's text still
                        // shows through, and white on it isn't readable.
                        Text("Tap the edges to turn pages and the middle for controls. Swipe to turn too.")
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
                    .accessibilityLabel(Text("Reading tips. Tap to dismiss."))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isVisible)
        .task {
            guard !hasShown else { return }
            // After the page is there, so the hint explains what's on screen.
            try? await Task.sleep(for: .seconds(1))
            // The controls would sit over the hint's labels.
            session.hideControls()
            isVisible = true
        }
    }

    private func dismiss() {
        hasShown = true
        isVisible = false
    }

    private func zone(_ title: LocalizedStringKey, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
            Text(title)
                .font(.footnote.weight(.medium))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
                .padding(4)
        }
    }
}
