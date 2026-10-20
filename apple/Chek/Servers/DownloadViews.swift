import SwiftUI

/// A quiet mark of something on the device, or on its way there.
struct DownloadIndicator: View {
    let state: Downloads.State

    var body: some View {
        switch state {
        case .none:
            EmptyView()
        case .waiting:
            Image(systemName: "arrow.down.circle.dotted")
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Waiting to download"))
        case .downloading(let fraction):
            // iOS draws a determinate circular progress as a spinner, so
            // the ring is drawn here.
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: max(fraction, 0.02))
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
            .animation(.linear(duration: 0.2), value: fraction)
            .accessibilityLabel(Text("Downloading"))
            .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
        case .downloaded:
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Downloaded"))
        }
    }
}

/// The one download action that fits the item's state.
struct DownloadAction: View {
    let item: Downloads.Item
    let state: Downloads.State
    @Environment(Downloads.self) private var downloads

    var body: some View {
        switch state {
        case .none:
            Button("Download", systemImage: "arrow.down.circle") {
                downloads.download([item])
            }
        case .waiting, .downloading:
            Button("Cancel Download", systemImage: "xmark.circle") {
                downloads.cancel(item)
            }
        case .downloaded:
            Button("Remove Download", systemImage: "trash") {
                downloads.remove(item)
            }
        }
    }
}

extension View {
    /// Gives a server comic's cell or row the download action in its
    /// context menu. Other items are left as they are.
    func comicDownloadMenu(for item: PublicationItem) -> some View {
        modifier(ComicDownloadMenu(item: item))
    }
}

private struct ComicDownloadMenu: ViewModifier {
    let item: PublicationItem
    @Environment(Downloads.self) private var downloads

    func body(content: Content) -> some View {
        if case .remote(let publication) = item.source, publication.kind == .comic, publication.isAvailable {
            content.contextMenu {
                DownloadAction(item: .comic(publication), state: downloads.state(of: publication.ref))
            }
        } else {
            content
        }
    }
}

/// The download mark beside a server comic's or source chapter's status.
struct ItemDownloadIndicator: View {
    let item: PublicationItem
    /// Whether the mark sits on a cover, where it needs a glass disc to
    /// read over the artwork. Nothing is drawn when there's no mark.
    var onCover = false
    @Environment(Downloads.self) private var downloads

    var body: some View {
        if case .local = item.source {
            EmptyView()
        } else {
            let state = downloads.state(of: item.id)
            if state != .none {
                if onCover {
                    DownloadIndicator(state: state)
                        .font(.footnote)
                        .padding(4)
                        .glassEffect(.regular, in: .circle)
                        .padding(4)
                } else {
                    DownloadIndicator(state: state)
                }
            }
        }
    }
}
