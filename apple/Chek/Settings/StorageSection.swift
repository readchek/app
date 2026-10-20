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
            LabeledContent("Library", value: sizes.map { $0.library.formatted(.byteCount(style: .file)) } ?? "…")
            LabeledContent("Downloads", value: sizes.map { $0.chapters.formatted(.byteCount(style: .file)) } ?? "…")
            LabeledContent("Server Books", value: sizes.map { $0.downloads.formatted(.byteCount(style: .file)) } ?? "…")
            LabeledContent("Covers", value: sizes.map { $0.covers.formatted(.byteCount(style: .file)) } ?? "…")
            Button("Clear Server Books and Covers") {
                isClearing = true
                Task {
                    await Self.clearCaches()
                    sizes = await Self.measure()
                    isClearing = false
                }
            }
            .disabled(isClearing || sizes.map { $0.downloads + $0.covers == 0 } ?? true)
            Button("Remove All Downloads…", role: .destructive) {
                isConfirmingChapterRemoval = true
            }
            .disabled(downloads.isEmpty)
        } header: {
            Text("Storage")
        } footer: {
            Text("Server books and covers come back as you read; your library, places and downloads stay until you remove them.")
        }
        .confirmationDialog("Remove All Downloads?", isPresented: $isConfirmingChapterRemoval, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                downloads.removeAll()
                Task { sizes = await Self.measure() }
            }
        } message: {
            Text("Downloaded chapters and comics can be downloaded again from their series.")
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
