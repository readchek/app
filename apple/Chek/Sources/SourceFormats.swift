import Foundation

/// What each installed source's chapters come in, as the server last said,
/// so a chapter from a source of comics opens at once, without first asking
/// whether it's a book.
nonisolated enum SourceFormats {
    private static let key = "sources.formats"

    /// Whether every chapter `source` serves is pages. False when it may
    /// serve files, or when nothing is known about it yet.
    static func readsOnlyPages(_ source: String, on server: UUID, defaults: UserDefaults = .standard) -> Bool {
        formats(of: source, on: server, defaults: defaults) == [ChekAPI.ContentFormat.images.rawValue]
    }

    /// Whether chapters from `source` can be kept for reading offline,
    /// which is done page by page. Books are kept once opened instead.
    static func canDownload(_ source: String, on server: UUID, defaults: UserDefaults = .standard) -> Bool {
        formats(of: source, on: server, defaults: defaults)?.contains(ChekAPI.ContentFormat.images.rawValue) ?? true
    }

    static func formats(of source: String, on server: UUID, defaults: UserDefaults = .standard) -> [String]? {
        let all = defaults.dictionary(forKey: key) as? [String: [String]]
        return all?["\(server.uuidString)/\(source)"]
    }

    /// Remembers the formats of everything installed on `server`.
    static func remember(_ installed: [ChekAPI.InstalledExtension], on server: UUID, defaults: UserDefaults = .standard) {
        var all = defaults.dictionary(forKey: key) as? [String: [String]] ?? [:]
        let prefix = "\(server.uuidString)/"
        all = all.filter { !$0.key.hasPrefix(prefix) }
        for site in installed {
            all[prefix + site.id] = (site.formats ?? [.images]).map(\.rawValue)
        }
        defaults.set(all, forKey: key)
    }
}
