import SwiftData
import SwiftUI

/// App settings: reading defaults and information about Chek.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                ServersSection()
                Section {
                    NavigationLink {
                        ReaderAppearanceForm()
                            .navigationTitle("Reading")
                    } label: {
                        Label("Reading", systemImage: "textformat.size")
                    }
                }
                StorageSection()
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

/// Your servers, with signing out and removing each one.
private struct ServersSection: View {
    @Query(sort: \ServerAccount.sortIndex) private var accounts: [ServerAccount]
    @Environment(AppRouter.self) private var router

    var body: some View {
        Section {
            ForEach(accounts) { account in
                NavigationLink {
                    ServerAccountForm(account: account)
                } label: {
                    ServerRow(account: account)
                }
            }
            Button("Connect a Server", systemImage: "plus") {
                router.sheet = .addServer
            }
        } header: {
            Text("Servers")
        }
    }
}

private struct ServerAccountForm: View {
    let account: ServerAccount
    @Environment(ServerStore.self) private var servers
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isConfirmingRemoval = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .onSubmit { servers.rename(account, to: name) }
                LabeledContent("Address", value: account.baseURL.absoluteString)
                LabeledContent("Account", value: account.userName)
            }
            Section {
                if servers.state(of: account.id) == .signedIn {
                    Button("Sign Out") {
                        Task { await servers.signOut(account) }
                    }
                } else {
                    Button("Sign In") {
                        router.sheet = .signIn(account.id)
                    }
                }
                Button("Remove Server", role: .destructive) {
                    isConfirmingRemoval = true
                }
            } footer: {
                Text("Removing the server forgets your places in its publications on this device. They stay saved on the server.")
            }
        }
        .navigationTitle(account.name)
        .onAppear { name = account.name }
        .onDisappear { servers.rename(account, to: name) }
        .confirmationDialog("Remove \(account.name)?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
            Button("Remove Server", role: .destructive) {
                Task {
                    await servers.remove(account)
                    dismiss()
                }
            }
        }
    }
}
