import SwiftUI

/// How much the app keeps on the device beyond the library, and a way to
/// clear what can be fetched again.
struct StorageSection: View {
    @State private var sizes: Sizes?
    @State private var isClearing = false

    struct Sizes: Equatable {
        var library: Int64
        var downloads: Int64
        var covers: Int64
    }

    var body: some View {
        Section {
            LabeledContent("Library", value: sizes.map { $0.library.formatted(.byteCount(style: .file)) } ?? "…")
            LabeledContent("Server Downloads", value: sizes.map { $0.downloads.formatted(.byteCount(style: .file)) } ?? "…")
            LabeledContent("Covers", value: sizes.map { $0.covers.formatted(.byteCount(style: .file)) } ?? "…")
            Button("Clear Downloads and Covers") {
                isClearing = true
                Task {
                    await Self.clearCaches()
                    sizes = await Self.measure()
                    isClearing = false
                }
            }
            .disabled(isClearing || sizes.map { $0.downloads + $0.covers == 0 } ?? true)
        } header: {
            Text("Storage")
        } footer: {
            Text("Downloads and covers come back as you read; your library and places stay.")
        }
        .task {
            sizes = await Self.measure()
        }
    }

    nonisolated private static func measure() async -> Sizes {
        Sizes(
            library: size(of: LibraryFiles.root),
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
