import SwiftUI

/// Connects a Chek server: its address, your name and your password.
struct AddServerView: View {
    @Environment(ServerStore.self) private var servers
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
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
        case address, name, password
    }

    private var canConnect: Bool {
        phase != .connecting && !address.isEmpty && !name.isEmpty && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("chek.example.com", text: $address)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .address)
                        .submitLabel(.next)
                        .onSubmit { focus = .name }
                } header: {
                    Text("Server")
                }
                Section {
                    TextField("Name", text: $name)
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
                } header: {
                    Text("Account")
                } footer: {
                    if case .failed(let error) = phase {
                        FormError(error: error)
                    } else {
                        Text("Your password goes only to this server. Chek keeps the session it gets back in your Keychain.")
                    }
                }
            }
            .disabled(phase == .connecting)
            .navigationTitle("Connect a Server")
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
                        Button("Connect", systemImage: "checkmark", action: connect)
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
                let account = try await servers.connect(address: address, name: name, password: password)
                router.sheet = nil
                router.tab = .browse
                router.browsePath = [.server(account.id)]
            } catch {
                phase = .failed(DisplayError(error))
            }
        }
    }
}

/// Signs in again to a server whose session ended.
struct SignInView: View {
    let account: UUID
    @Environment(ServerStore.self) private var servers
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var phase = AddServerView.Phase.editing
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            if let server = servers.account(account) {
                Form {
                    Section {
                        LabeledContent("Server", value: server.name)
                        LabeledContent("Name", value: server.userName)
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
                .disabled(phase == .connecting)
                .navigationTitle("Sign In")
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
                            Button("Sign In", systemImage: "checkmark") {
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
            } catch {
                phase = .failed(DisplayError(error))
            }
        }
    }
}

private struct FormError: View {
    let error: DisplayError

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(error.title, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            if let message = error.message {
                Text(message)
            }
        }
    }
}
