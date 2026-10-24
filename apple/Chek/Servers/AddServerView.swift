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
                    TextField("Name", text: $displayName, prompt: Text(Self.suggestedName(for: address) ?? String(localized: "Name (Optional)")))
                        .focused($focus, equals: .displayName)
                        .submitLabel(.next)
                        .onSubmit { focus = .name }
                } footer: {
                    // An error sits under the field it's about.
                    if case .failed(let error) = phase, !Self.isCredentialError(error) {
                        FormError(error: error)
                    } else {
                        Text("Enter the address you were given. A name helps tell libraries apart and is only shown on this device.")
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

extension AddServerView {
    /// The host name a server is called by when no name is given, shown as
    /// the name field's placeholder.
    static func suggestedName(for address: String) -> String? {
        guard let host = ServerStore.baseURL(from: address)?.host(), host.contains(".") || host == "localhost" else { return nil }
        return host
    }
}

/// Signs in again to a server whose session ended.
struct SignInView: View {
    let account: UUID
    @Environment(ServerStore.self) private var servers
    @Environment(ServerSync.self) private var sync
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var phase = AddServerView.Phase.editing
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            if let server = servers.account(account) {
                Form {
                    Section {
                        LabeledContent("Library", value: server.name)
                        LabeledContent("User Name", value: server.userName)
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .focused($isFocused)
                            .submitLabel(.go)
                            .onSubmit { signIn(server) }
                    } footer: {
                        if case .failed(let error) = phase {
                            FormError(error: error)
                        }
                    }
                }
                .onChange(of: password) {
                    if case .failed = phase { phase = .editing }
                }
                .navigationTitle("Sign In")
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
                            .disabled(password.isEmpty)
                        }
                    }
                }
                .onAppear { isFocused = true }
            }
        }
    }

    private func signIn(_ server: ServerAccount) {
        guard !password.isEmpty, phase != .connecting else { return }
        phase = .connecting
        Task {
            do {
                try await servers.signIn(server, password: password)
                dismiss()
                router.resumePendingOpen(using: sync)
            } catch {
                phase = .failed(DisplayError(error))
                isFocused = true
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
