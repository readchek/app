import ChekReader
import SwiftUI

/// Asks whether to jump to where you are on another device, when the
/// server has a place there that differs from the one here.
struct OtherDevicePrompt: View {
    let session: ReaderSession
    @Environment(ServerSync.self) private var sync

    var body: some View {
        if let prompt = sync.prompts[session.item.ref], session.controller.state == .ready {
            VStack {
                Spacer()
                PromptCard(prompt: prompt) {
                    if let locator = sync.useOtherDevicePosition(for: session.item.ref) {
                        Task { await session.controller.go(to: locator) }
                    }
                } stay: {
                    sync.keepThisDevicePosition(for: session.item.ref)
                }
                .padding(.horizontal)
                .padding(.bottom, session.isShowingControls ? 110 : 24)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

private struct PromptCard: View {
    let prompt: OtherDevicePosition
    let jump: () -> Void
    let stay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.subheadline.weight(.semibold))
                    if let updatedAt = prompt.updatedAt {
                        Text(updatedAt, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Button("Stay Here", action: stay)
                    .buttonStyle(.glass)
                Spacer()
                Button("Go There", action: jump)
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var headline: String {
        let place = prompt.locator.locations.totalProgression.map { $0.formatted(.percent.precision(.fractionLength(0))) }
        switch (prompt.device, place) {
        case let (device?, place?): return String(localized: "You're at \(place) on \(device)")
        case let (nil, place?): return String(localized: "You're at \(place) on another device")
        case let (device?, nil): return String(localized: "You're further along on \(device)")
        case (nil, nil): return String(localized: "You're somewhere else on another device")
        }
    }
}
