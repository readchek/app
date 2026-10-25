import SwiftUI

/// The terms an openly licensed book came with, as its source gave them:
/// the license, the credit it asks for and where the book is from.
struct RightsSection: View {
    let rights: ChekAPI.Rights

    var body: some View {
        Section {
            if let license = rights.license {
                if let url = Self.link(rights.licenseUrl) {
                    Link(destination: url) {
                        LabeledContent {
                            Text(license)
                                .foregroundStyle(.tint)
                        } label: {
                            Text("License")
                                .foregroundStyle(.primary)
                        }
                    }
                } else {
                    LabeledContent("License", value: license)
                }
            }
            if let attribution = rights.attribution {
                Text(attribution)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let url = Self.link(rights.sourceUrl) {
                Link(destination: url) {
                    Label("Visit the Book's Page", systemImage: "safari")
                }
            }
        } footer: {
            Text("This book is shared openly by the site it comes from, on these terms.")
        }
    }

    /// Only secure web links are followed, since they come from a site.
    static func link(_ string: String?) -> URL? {
        guard let string, let url = URL(string: string), url.scheme?.lowercased() == "https", url.host() != nil else { return nil }
        return url
    }
}
