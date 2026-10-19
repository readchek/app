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
        // Keys hold slashes; hex keeps them a single safe file name.
        let name = Data(key.utf8).map { String(format: "%02x", $0) }.joined()
        return diskFolder.appending(path: name)
    }

    nonisolated static func diskData(for key: String) -> Data? {
        try? Data(contentsOf: diskURL(for: key))
    }

    nonisolated static func storeOnDisk(_ data: Data, for key: String) {
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
