import SwiftUI

/// Adds a library someone shares with you: its address, your user name
/// and your password.
struct AddServerView: View {
    @Environment(ServerStore.self) private var servers
    @Environment(SiteUpdates.self) private var siteUpdates
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var displayName = ""
    @State private var name = ""
    @State private var password = ""
    @State private var phase = Phase.editing
    @FocusState private var focus: Field?

    enum Phase: Equatable {
        case editing
        case connecting
        case failed(DisplayError)
    }

    enum Field {
        case address, displayName, name, password
    }

    private var canConnect: Bool {
        phase != .connecting && !address.isEmpty && !name.isEmpty && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Address", text: $address, prompt: Text(verbatim: "books.example.com"))
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .address)
                        .submitLabel(.next)
                        .onSubmit { focus = .displayName }
                    TextField("Library Name", text: $displayName, prompt: Text("Library Name (Optional)"))
                        .focused($focus, equals: .displayName)
                        .submitLabel(.next)
                        .onSubmit { focus = .name }
                } footer: {
                    // An error sits under the field it's about.
                    if case .failed(let error) = phase, !Self.isCredentialError(error) {
                        FormError(error: error)
                    } else {
                        Text("Enter the address you were given. A name helps tell libraries apart and is only shown on this device. Without one, the library goes by its address.")
                    }
                }
                Section {
                    TextField("User Name", text: $name)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(connect)
                } footer: {
                    if case .failed(let error) = phase, Self.isCredentialError(error) {
                        FormError(error: error)
                    } else {
                        Text("Your password is sent only to this library.")
                    }
                }
            }
            // Typing again after a failure means you're fixing it, so the
            // old message goes rather than nagging under the new text.
            .onChange(of: [address, name, password]) {
                if case .failed = phase { phase = .editing }
            }
            .navigationTitle("Add Shared Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if phase == .connecting {
                        ProgressView()
                    } else {
                        Button("Add", role: .confirm, action: connect)
                            .disabled(!canConnect)
                    }
                }
            }
            .onAppear { focus = .address }
        }
        .interactiveDismissDisabled(phase == .connecting)
    }

    private func connect() {
        guard canConnect else { return }
        phase = .connecting
        Task {
            do {
                let account = try await servers.connect(address: address, displayName: displayName, name: name, password: password)
                Task { await siteUpdates.check(account.id, force: true) }
                router.sheet = nil
                router.tab = .browse
                router.browsePath = [.server(account.id)]
            } catch {
                let failure = DisplayError(error)
                phase = .failed(failure)
                // Back to the field at fault, so fixing it is one tap fewer.
                focus = Self.isCredentialError(failure) ? .password : .address
            }
        }
    }

    /// Whether a failure is about the user name or password rather than
    /// the address.
    private static func isCredentialError(_ error: DisplayError) -> Bool {
        error.title == String(localized: "Incorrect User Name or Password")
    }
}

/// Signs in to a library you've already added: again after its session
/// ended, or as someone else, keeping the library in your list.
struct SignInView: View {
    let account: UUID
    /// Whether this was opened to sign in as another person, so the user
    /// name starts empty rather than as the person signed in now.
    var isChangingUser = false
    @Environment(ServerStore.self) private var servers
    @Environment(ServerSync.self) private var sync
    @Environment(SiteUpdates.self) private var siteUpdates
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var password = ""
    @State private var phase = AddServerView.Phase.editing
    @FocusState private var focus: AddServerView.Field?

    private var canSignIn: Bool {
        phase != .connecting && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            if let server = servers.account(account) {
                Form {
                    Section {
                        LabeledContent("Library", value: server.name)
                        TextField("User Name", text: $name)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focus = .password }
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .focused($focus, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { signIn(server) }
                    } footer: {
                        if case .failed(let error) = phase {
                            FormError(error: error)
                        } else if isChangingUser {
                            Text("You stay signed in as \(server.userName) until this works. Places and downloads kept on this device for \(server.userName) are then removed. Their reading positions stay on the library.")
                        }
                    }
                }
                .onChange(of: [name, password]) {
                    if case .failed = phase { phase = .editing }
                }
                .navigationTitle(isChangingUser ? "Change User" : "Sign In")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", systemImage: "xmark") {
                            router.dropPendingOpen()
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if phase == .connecting {
                            ProgressView()
                        } else {
                            Button("Sign In", role: .confirm) {
                                signIn(server)
                            }
                            .disabled(!canSignIn)
                        }
                    }
                }
                .onAppear {
                    if isChangingUser {
                        focus = .name
                    } else {
                        name = server.userName
                        focus = .password
                    }
                }
            }
        }
        .interactiveDismissDisabled(phase == .connecting)
    }

    private func signIn(_ server: ServerAccount) {
        guard canSignIn else { return }
        phase = .connecting
        let before = server.userID
        Task {
            do {
                if isChangingUser {
                    // Places still waiting to go up belong to the person
                    // signed in now, and are dropped if someone else signs in.
                    await sync.uploadPending()
                }
                try await servers.signIn(server, as: name, password: password)
                if server.userID != before {
                    // Screens open on this library showed the person before.
                    router.serverUserChanged(server.id)
                    Task { await siteUpdates.check(server.id, force: true) }
                }
                dismiss()
                router.resumePendingOpen(using: sync)
            } catch {
                let shown = DisplayError(error)
                phase = .failed(shown)
                focus = shown.title == String(localized: "Already Added") ? .name : .password
            }
        }
    }
}

/// An error under the fields it's about, in words alone: the color says
/// it's an error, so a warning symbol would only shout.
struct FormError: View {
    let error: DisplayError

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(error.title)
                .foregroundStyle(.red)
            if let message = error.message {
                Text(message)
            }
        }
    }
}
