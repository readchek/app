import SwiftUI

/// App settings: reading defaults and information about Chek.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        ReaderAppearanceForm()
                            .navigationTitle("Reading")
                    } label: {
                        Label("Reading", systemImage: "textformat.size")
                    }
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.versionDescription)
                    Link(destination: URL(string: "https://chek.page")!) {
                        Label("chek.page", systemImage: "safari")
                    }
                    Link(destination: URL(string: "https://github.com/readchek/app/issues")!) {
                        Label("Report a Problem", systemImage: "exclamationmark.bubble")
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Chek is the successor to Chibi Manga.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private extension Bundle {
    var versionDescription: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}
