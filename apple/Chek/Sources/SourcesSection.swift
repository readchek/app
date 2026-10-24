import SwiftUI

/// The sites added to a library, each leading to what it offers, and a
/// row for adding more.
struct SourcesSection: View {
    let account: UUID
    let sources: [ChekAPI.InstalledExtension]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Sites")
            ForEach(sources) { source in
                NavigationRow(
                    title: source.name,
                    systemImage: "globe",
                    value: Route.source(account, source),
                    detail: source.usable ? nil : String(localized: "Turned Off"),
                    isDimmed: !source.usable
                )
            }
            let updates = sources.filter { $0.update != nil }.count
            NavigationRow(
                title: sources.isEmpty ? String(localized: "Add Sites") : String(localized: "Add or Remove Sites"),
                systemImage: "plus.circle",
                value: Route.extensions(account),
                showsDivider: false,
                detail: updates > 0 ? String(AttributedString(localized: "^[\(updates) update](inflect: true)").characters) : nil
            )
        }
    }
}

extension ServerStore {
    /// An image a source route returned, fetched through the server with
    /// `account`'s credentials and kept like any other cover.
    func sourceImage(_ path: String?, on account: UUID) -> CoverSource {
        guard let path, let client = client(for: account), let request = client.imageRequest(path) else { return .none }
        return .remote(key: "source/\(account.uuidString)/\(path)", request: request)
    }
}
