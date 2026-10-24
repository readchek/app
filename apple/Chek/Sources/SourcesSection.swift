import SwiftUI

/// The sites added to a library, each leading to what it offers, and a
/// row for adding more. Rows of a shelf page's list, under their header.
struct SourcesSection: View {
    let account: UUID
    let sources: [ChekAPI.InstalledExtension]

    var body: some View {
        SectionHeader(title: "Sites")
            .headerRow()
        ForEach(sources) { source in
            NavigationLink(value: Route.source(account, source)) {
                LabeledContent {
                    if !source.usable {
                        Text("Off")
                    }
                } label: {
                    // Only the name dims when the site is off; the symbol
                    // keeps the tint every row's symbol has.
                    Label {
                        Text(source.name)
                            .foregroundStyle(source.usable ? .primary : .secondary)
                    } icon: {
                        Image(systemName: "globe")
                    }
                }
            }
        }
        let updates = sources.filter { $0.update != nil }.count
        NavigationLink(value: Route.extensions(account)) {
            LabeledContent {
                if updates > 0 {
                    Text("^[\(updates) update](inflect: true)")
                }
            } label: {
                // Adding is a plus; managing what's there is an edit.
                if sources.isEmpty {
                    Label("Add Sites", systemImage: "plus")
                } else {
                    Label("Manage Sites", systemImage: "pencil")
                }
            }
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
