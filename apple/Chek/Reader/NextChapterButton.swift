import ChekReader
import SwiftUI

/// On a source chapter's last page, the way on to the next chapter, as a
/// glass button above the controls. It looks the next chapter up once,
/// when the last page is reached.
struct NextChapterButton: View {
    let session: ReaderSession
    let chapter: SourceChapterRef
    let open: (ReadingItem) -> Void
    @Environment(ServerSync.self) private var sync
    @State private var lookup: LoadState<ServerSync.NextChapter> = .idle

    var body: some View {
        VStack {
            Spacer()
            if isOnLastPage, case .loaded(.next(let next)) = lookup {
                Button {
                    if let item = try? sync.readingItem(for: next) {
                        open(item)
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Next Chapter")
                                .font(.subheadline.weight(.semibold))
                            Text(next.chapterTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } icon: {
                        Image(systemName: "arrow.forward")
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if isOnLastPage, case .loaded(.end) = lookup {
                Text("You're up to date")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .transition(.opacity)
            } else if isOnLastPage, case .loaded(.unknown) = lookup {
                // Offline, most likely: not the end, just not known.
                Button {
                    lookup = .idle
                    look()
                } label: {
                    Label("Couldn't check for the next chapter", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glass)
                .transition(.opacity)
            }
        }
        .padding(.bottom, 16)
        .padding(.horizontal, Metrics.margin)
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: isOnLastPage)
        .animation(.snappy, value: lookup)
        .onChange(of: isOnLastPage, initial: true) { _, last in
            if last {
                look()
            }
        }
    }

    private func look() {
        guard case .idle = lookup else { return }
        lookup = .loading
        Task {
            lookup = .loaded(await sync.chapter(after: chapter))
        }
    }

    private var isOnLastPage: Bool {
        guard let count = session.controller.positions?.count, count > 0,
              let position = session.controller.location?.locations.position
        else { return false }
        return position >= count
    }
}
