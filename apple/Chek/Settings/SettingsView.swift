import SwiftData
import SwiftUI
import UserNotifications

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
                NewChapterAlertsSection()
                StorageSection()
                DemoSection()
                Section {
                    LabeledContent("Version", value: Bundle.main.versionDescription)
                    Link(destination: URL(string: "https://chek.page")!) {
                        Label("chek.page", systemImage: "safari")
                    }
                    // Email or GitHub, so reporting needs no GitHub account.
                    Link(destination: URL(string: "https://chek.page/support")!) {
                        Label("Report a Problem", systemImage: "exclamationmark.bubble")
                    }
                    Link(destination: URL(string: "https://chek.page/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
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

/// The demo: a temporary connection to the public demo server, with
/// sample publications of every kind Chek reads.
private struct DemoSection: View {
    @Environment(ServerStore.self) private var servers
    @Environment(AppRouter.self) private var router

    var body: some View {
        Section {
            if servers.isDemo {
                Button("Exit the Demo", role: .destructive) {
                    Task {
                        await servers.endDemo()
                        router.serverRemoved(DemoMode.accountID)
                    }
                }
            } else {
                TryDemoButton()
            }
        } header: {
            Text("Demo")
        } footer: {
            Text(servers.isDemo
                ? "You're reading sample books from demo.chek.page. The demo ends on its own when Chek is closed, and your places in it stay on this device."
                : "Connects to demo.chek.page for a look at books, comics and sources of every kind Chek reads. Nothing is kept once Chek is closed.")
        }
    }
}

/// Whether new chapters in followed series are announced, which iOS
/// decides, with the way to change it.
private struct NewChapterAlertsSection: View {
    @State private var status: UNAuthorizationStatus?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section {
            LabeledContent {
                switch status {
                case .authorized, .provisional, .ephemeral:
                    Text("On")
                case .denied:
                    Text("Off")
                case .notDetermined, nil:
                    Text("Not Yet Asked")
                @unknown default:
                    Text("Off")
                }
            } label: {
                Label("New Chapter Alerts", systemImage: "bell.badge")
            }
            if status == .notDetermined {
                Button("Turn On Alerts") {
                    Task {
                        await FollowNotifications.askIfNeeded()
                        await refresh()
                    }
                }
            } else if status != nil, let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                Link("Change in Settings", destination: url)
            }
        } header: {
            Text("Following")
        } footer: {
            Text("Chek checks the series you follow a few times a day and tells you when a chapter is out.")
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            // Back from the Settings app, where it may have changed.
            if phase == .active {
                Task { await refresh() }
            }
        }
    }

    private func refresh() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
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

    private var isDemo: Bool { account.id == DemoMode.accountID }

    var body: some View {
        Form {
            Section {
                if isDemo {
                    LabeledContent("Name", value: account.name)
                } else {
                    LabeledContent("Name") {
                        TextField("Name", text: $name)
                            .multilineTextAlignment(.trailing)
                            .onSubmit { servers.rename(account, to: name) }
                    }
                }
                LabeledContent("Address", value: account.baseURL.absoluteString)
                LabeledContent("Account", value: account.userName)
            }
            if isDemo {
                // The demo has one way out, not a sign-out and a removal
                // that would need its public password to undo.
                Section {
                    Button("Exit the Demo", role: .destructive) {
                        Task {
                            await servers.endDemo()
                            dismiss()
                        }
                    }
                } footer: {
                    Text("The demo ends on its own when Chek is closed. Exiting now forgets it straight away.")
                }
            } else {
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
                    Text("Removing the server forgets your places in its publications on this device, and deletes what you downloaded from it. Your places stay saved on the server.")
                }
            }
        }
        .navigationTitle(account.name)
        .onAppear { name = account.name }
        .onDisappear {
            if !isDemo {
                servers.rename(account, to: name)
            }
        }
        .confirmationDialog("Remove \(account.name)?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
            Button("Remove Server", role: .destructive) {
                router.serverRemoved(account.id)
                Task {
                    await servers.remove(account)
                    dismiss()
                }
            }
        }
    }
}
