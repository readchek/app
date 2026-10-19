import SwiftUI

/// The sources installed on a server, each leading to its series, and a
/// row for getting more.
struct SourcesSection: View {
    let account: UUID
    let sources: [ChekAPI.InstalledExtension]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Sources")
            ForEach(sources) { source in
                NavigationRow(
                    title: source.name,
                    systemImage: "globe",
                    value: Route.source(account, source),
                    detail: source.usable ? nil : String(localized: "Not Allowed"),
                    isDimmed: !source.usable
                )
            }
            let updates = sources.filter { $0.update != nil }.count
            NavigationRow(
                title: sources.isEmpty ? String(localized: "Get Sources") : String(localized: "Manage Sources"),
                systemImage: "puzzlepiece.extension",
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
