import CryptoKit
import Foundation
import UIKit

/// Loads and decodes cover images off the main thread, and keeps recent
/// ones in memory so scrolling back never flashes a placeholder.
@MainActor
final class ImagePipeline {
    static let shared = ImagePipeline()

    private let memory = NSCache<NSString, UIImage>()
    /// Loads in flight, so two views asking for the same image share one.
    private var loads: [String: Task<UIImage?, Never>] = [:]

    private init() {
        memory.countLimit = 300
    }

    /// The image already in memory for `key`, for showing on first draw.
    func cachedImage(for key: String) -> UIImage? {
        memory.object(forKey: key as NSString)
    }

    /// The image for `key`, loading it with `load` if it isn't in memory.
    func image(for key: String, load: @escaping @Sendable () async -> UIImage?) async -> UIImage? {
        if let image = memory.object(forKey: key as NSString) {
            return image
        }
        if let running = loads[key] {
            return await running.value
        }
        let task = Task { await load() }
        loads[key] = task
        let image = await task.value
        loads[key] = nil
        if let image {
            memory.setObject(image, forKey: key as NSString)
        }
        return image
    }

    func removeImage(for key: String) {
        memory.removeObject(forKey: key as NSString)
    }

    /// Where downloaded covers are kept between launches. Caches, since
    /// they can always be fetched again.
    nonisolated private static let diskFolder = URL.cachesDirectory.appending(path: "Covers", directoryHint: .isDirectory)

    nonisolated private static func diskURL(for key: String) -> URL {
        // Keys hold slashes and can run to hundreds of characters, as a
        // source image's does, past what a file name allows; a digest is
        // always one short safe name.
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return diskFolder.appending(path: digest)
    }

    /// Files named the old way, by the key itself in hex, are never read
    /// again, so the folder is emptied once and marked.
    nonisolated private static let diskFolderReady: Void = {
        let marker = diskFolder.appending(path: ".v2")
        guard !FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)) else { return }
        try? FileManager.default.removeItem(at: diskFolder)
        try? FileManager.default.createDirectory(at: diskFolder, withIntermediateDirectories: true)
        try? Data().write(to: marker)
    }()

    nonisolated static func diskData(for key: String) -> Data? {
        _ = diskFolderReady
        return try? Data(contentsOf: diskURL(for: key))
    }

    nonisolated static func storeOnDisk(_ data: Data, for key: String) {
        _ = diskFolderReady
        try? FileManager.default.createDirectory(at: diskFolder, withIntermediateDirectories: true)
        try? data.write(to: diskURL(for: key), options: .atomic)
    }

    /// Decodes an image file into a bitmap ready to draw.
    @concurrent
    nonisolated static func decodeFile(at url: URL) async -> UIImage? {
        await UIImage(contentsOfFile: url.path(percentEncoded: false))?.byPreparingForDisplay()
    }

    /// Decodes image bytes into a bitmap ready to draw.
    @concurrent
    nonisolated static func decode(_ data: Data) async -> UIImage? {
        await UIImage(data: data)?.byPreparingForDisplay()
    }
}
