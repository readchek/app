import ChekReader
import SwiftUI

/// The table of contents, with the chapter you're in marked.
struct ContentsPanel: View {
    let session: ReaderSession
    @Environment(\.dismiss) private var dismiss
    /// Entries flattened with their depth, worked out once when the panel opens.
    @State private var entries: [ContentsEntry] = []
    @State private var currentEntry: ContentsEntry.ID?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(entries) { entry in
                    Button {
                        Task { await session.go(to: entry.link) }
                    } label: {
                        ContentsRow(title: entry.title, depth: entry.depth, isCurrent: entry.id == currentEntry)
                    }
                    .id(entry.id)
                }
                .listStyle(.plain)
                .overlay {
                    if entries.isEmpty {
                        EmptyState("This book doesn't have a table of contents.", systemImage: "list.bullet")
                    }
                }
                .onAppear {
                    load()
                    if let currentEntry {
                        proxy.scrollTo(currentEntry, anchor: .center)
                    }
                }
            }
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Nothing is saved here, so the panel closes rather than
                // finishing, with the same button as the reader itself.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func load() {
        guard entries.isEmpty, let publication = session.controller.publication else { return }
        entries = ContentsEntry.flatten(publication.tableOfContents)
        // The current chapter is the last entry at or before the location.
        guard let location = session.controller.location,
              let index = publication.readingOrderIndex(of: location)
        else { return }
        currentEntry = entries.last { entry in
            guard let locator = publication.locator(for: entry.link),
                  let entryIndex = publication.readingOrderIndex(of: locator)
            else { return false }
            return entryIndex <= index
        }?.id
    }
}

struct ContentsEntry: Identifiable, Hashable {
    let id: Int
    let title: String
    let depth: Int
    let link: ChekReader.Link

    static func flatten(_ links: [ChekReader.Link]) -> [ContentsEntry] {
        var entries: [ContentsEntry] = []
        func visit(_ links: [ChekReader.Link], depth: Int) {
            for link in links {
                entries.append(ContentsEntry(id: entries.count, title: link.title ?? link.href, depth: depth, link: link))
                visit(link.children, depth: depth + 1)
            }
        }
        visit(links, depth: 0)
        return entries
    }
}

private struct ContentsRow: View {
    let title: String
    let depth: Int
    let isCurrent: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(depth == 0 ? .body : .subheadline)
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(depth == 0 ? .primary : .secondary))
                .padding(.leading, CGFloat(min(depth, 4)) * 16)
            Spacer()
            if isCurrent {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel(Text("Current chapter"))
            }
        }
        .contentShape(.rect)
    }
}
