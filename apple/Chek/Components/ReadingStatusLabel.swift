import SwiftUI

/// Where you are in a publication, in a word: New, a percentage or
/// Finished, as Books shows under each cover.
struct ReadingStatusLabel: View {
    let status: ReadingStatus

    var body: some View {
        switch status {
        case .new:
            Text("New")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundStyle(.white)
                .background(.tint, in: .capsule)
        case .started:
            Text("Started")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .inProgress(let progress):
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        case .finished:
            Label("Finished", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// A thin bar showing progress through a publication.
struct ReadingProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(.quaternary)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.tint)
                        .frame(width: max(4, geometry.size.width * progress))
                }
        }
        .frame(height: 3)
        .accessibilityElement()
        .accessibilityLabel(Text("Reading progress"))
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}
