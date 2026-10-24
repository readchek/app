import SwiftUI

/// A screen that's loading: the system spinner, centered, at its usual
/// size. It waits a moment before showing, so a load that finishes at
/// once never flashes one.
struct LoadingState: View {
    @State private var isShowing = false

    var body: some View {
        ZStack {
            if isShowing {
                ProgressView()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) {
                isShowing = true
            }
        }
    }
}
