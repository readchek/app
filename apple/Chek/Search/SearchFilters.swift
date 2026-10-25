import Foundation

/// Where a search looks: everywhere at once, or only one place.
enum SearchScope: Hashable {
    case everywhere
    /// The books and comics on this device.
    case library
    /// One shared library's own publications.
    case server(UUID)
    /// One site added to a shared library, by the library and the site.
    case source(UUID, String)
}

/// What a search is narrowed to.
struct SearchFilters: Hashable {
    var scope = SearchScope.everywhere
    /// Only books or only comics, or nil for both.
    var kind: PublicationKind?

    var isActive: Bool {
        scope != .everywhere || kind != nil
    }

    /// Whether a site's chapters can be `kind`, by the formats it reads.
    /// Sites from before formats existed read pages.
    static func source(_ source: ChekAPI.InstalledExtension, matches kind: PublicationKind?) -> Bool {
        guard let kind else { return true }
        let formats = source.formats ?? [.images]
        switch kind {
        case .comic: return formats.contains(.images)
        case .book: return formats.contains(.epub) || formats.contains(.pdf)
        }
    }
}
