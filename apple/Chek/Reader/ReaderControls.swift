import ChekReader
import SwiftUI

/// The controls drawn over the page: a bar at the top to close, find your
/// way and change how text looks, and your place in the book at the bottom.
struct ReaderControls: View {
    let session: ReaderSession

    var body: some View {
        VStack(spacing: 0) {
            if session.isShowingControls {
                ReaderTopBar(session: session)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
            if session.isShowingControls, session.controller.state == .ready {
                ReaderBottomBar(controller: session.controller)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .sheet(item: Bindable(session).panel) { panel in
            switch panel {
            case .contents:
                ContentsPanel(session: session)
            case .appearance:
                AppearancePanel()
            }
        }
    }
}

private struct ReaderTopBar: View {
    let session: ReaderSession
    @Environment(AppRouter.self) private var router

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button("Close", systemImage: "xmark") {
                    router.closeReader()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)

                ReaderTitle(title: session.item.title, chapter: session.controller.location?.title)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 0) {
                    Button("Contents", systemImage: "list.bullet") {
                        session.show(.contents)
                    }
                    if session.item.kind == .book {
                        Button("Appearance", systemImage: "textformat.size") {
                            session.show(.appearance)
                        }
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(session.controller.state != .ready)
            }
        }
    }
}

/// The book's title, with the chapter you're in under it.
private struct ReaderTitle: View {
    let title: String
    let chapter: String?

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if let chapter, chapter != title {
                Text(chapter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

/// A scrubber through the whole publication, with the page you're on.
private struct ReaderBottomBar: View {
    let controller: ReaderController
    /// Where the scrubber is while you drag it, before the reader moves.
    @State private var scrubbing: Double?

    /// Fixed pages, as in comics and PDFs, have real page numbers. Text
    /// that reflows has positions instead, which aren't pages you'd
    /// recognize, so it shows the chapter.
    private var showsPages: Bool {
        guard let format = controller.format else { return false }
        return [.pdf, .cbz, .cbt, .cbr, .cb7].contains(format)
    }

    var body: some View {
        let count = controller.positions?.count ?? 0
        let position = controller.location?.locations.position
        VStack(spacing: 6) {
            if count > 1 {
                Slider(
                    value: Binding(
                        get: { scrubbing ?? Double(position ?? 1) },
                        set: { scrubbing = $0 }
                    ),
                    in: 1...Double(count),
                    step: 1
                ) { editing in
                    guard !editing, let target = scrubbing else { return }
                    Task {
                        await controller.go(toPosition: Int(target))
                        scrubbing = nil
                    }
                }
                .accessibilityLabel(Text("Page"))
                .accessibilityValue(Text("\(Int(scrubbing ?? Double(position ?? 1))) of \(count)"))
            } else {
                ProgressView(value: controller.location?.locations.totalProgression ?? 0)
            }
            HStack {
                if let target = scrubbing, showsPages {
                    Text("Page \(Int(target)) of \(count)")
                } else if showsPages, let position, count > 0 {
                    Text("Page \(position) of \(count)")
                } else if let chapter = controller.location?.title {
                    Text(chapter)
                        .lineLimit(1)
                }
                Spacer()
                if let progress = scrubbing.map({ ($0 - 1) / Double(max(count - 1, 1)) }) ?? controller.location?.locations.totalProgression {
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}
