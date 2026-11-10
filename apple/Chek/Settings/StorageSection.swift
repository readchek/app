import SwiftUI

/// How much the app keeps on the device beyond the library, and a way to
/// clear what can be fetched again.
struct StorageSection: View {
    @State private var sizes: Sizes?
    @State private var isClearing = false
    @State private var isConfirmingChapterRemoval = false
    @Environment(Downloads.self) private var downloads

    struct Sizes: Equatable {
        var library: Int64
        var chapters: Int64
        var downloads: Int64
        var covers: Int64
    }

    var body: some View {
        Section {
            if let sizes, sizes.library + sizes.chapters + sizes.downloads + sizes.covers == 0 {
                // One line rather than four zeros over two dead buttons.
                Text("Nothing stored yet.")
                    .foregroundStyle(.secondary)
            } else {
                // "0 KB", not the formatter's "Zero KB".
                LabeledContent("Library", value: sizes.map { $0.library.formatted(.byteCount(style: .file, spellsOutZero: false)) } ?? "…")
                LabeledContent("Downloads", value: sizes.map { $0.chapters.formatted(.byteCount(style: .file, spellsOutZero: false)) } ?? "…")
                LabeledContent("Recently Read", value: sizes.map { $0.downloads.formatted(.byteCount(style: .file, spellsOutZero: false)) } ?? "…")
                LabeledContent("Cover Images", value: sizes.map { $0.covers.formatted(.byteCount(style: .file, spellsOutZero: false)) } ?? "…")
                // Each action only while it has something to act on.
                if let sizes, sizes.downloads + sizes.covers > 0 {
                    Button("Free Up Space") {
                        isClearing = true
                        Task {
                            await Self.clearCaches()
                            self.sizes = await Self.measure()
                            isClearing = false
                        }
                    }
                    .disabled(isClearing)
                }
                if !downloads.isEmpty {
                    Button("Remove All Downloads", role: .destructive) {
                        isConfirmingChapterRemoval = true
                    }
                }
            }
        } header: {
            Text("Storage")
        } footer: {
            Text("Freeing up space clears copies of recently read books from shared libraries and cover images. They're fetched again as you read. Your library, downloads, and reading positions are kept.")
        }
        .confirmationDialog("Remove All Downloads?", isPresented: $isConfirmingChapterRemoval, titleVisibility: .visible) {
            Button("Remove Downloads", role: .destructive) {
                downloads.removeAll()
                Task { sizes = await Self.measure() }
            }
        } message: {
            Text("You can download them again any time.")
        }
        .task {
            sizes = await Self.measure()
        }
    }

    nonisolated private static func measure() async -> Sizes {
        Sizes(
            library: size(of: LibraryFiles.root),
            chapters: size(of: ChapterFiles.root) + size(of: PublicationFiles.root),
            downloads: size(of: URL.cachesDirectory.appending(path: "Servers")),
            covers: size(of: URL.cachesDirectory.appending(path: "Covers"))
        )
    }

    nonisolated private static func clearCaches() async {
        try? FileManager.default.removeItem(at: URL.cachesDirectory.appending(path: "Servers"))
        try? FileManager.default.removeItem(at: URL.cachesDirectory.appending(path: "Covers"))
    }

    nonisolated private static func size(of folder: URL) -> Int64 {
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }
}
