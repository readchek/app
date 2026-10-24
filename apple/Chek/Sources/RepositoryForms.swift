import SwiftUI

/// Adds an extension repository to a server, signing in to it when it's
/// private.
struct AddRepositoryView: View {
    let model: ExtensionsModel
    /// Whether it goes on the admin's list, which everyone sees.
    let isShared: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var signIn = RepositorySignIn()
    @State private var phase = AddServerView.Phase.editing
    @FocusState private var isAddressFocused: Bool

    private var canAdd: Bool {
        phase != .connecting
            && !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && signIn.isComplete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Address", text: $address, prompt: Text(verbatim: "chek.page/extensions"))
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isAddressFocused)
                        .submitLabel(.go)
                        .onSubmit(add)
                } header: {
                    Text("Repository")
                } footer: {
                    Text(isShared ? "The folder holding its index.json, or a GitHub repository as github:owner/repo. Everyone on this server can install from it." : "The folder holding its index.json, or a GitHub repository as github:owner/repo. Only you see it.")
                }
                RepositorySignInSection(signIn: $signIn, phase: phase)
            }
            // Typing again after a failure means you're fixing it.
            .onChange(of: address) {
                if case .failed = phase { phase = .editing }
            }
            .onChange(of: signIn) { old, new in
                // Switching kind, by hand or because the repository asked,
                // keeps the message, which says what to choose; typing
                // clears it.
                if case .failed = phase, old.kind == new.kind { phase = .editing }
            }
            .navigationTitle("Add Repository")
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
                        Button("Add", systemImage: "checkmark", action: add)
                            .disabled(!canAdd)
                    }
                }
            }
            .onAppear { isAddressFocused = true }
        }
        .interactiveDismissDisabled(phase == .connecting)
    }

    private func add() {
        guard canAdd else { return }
        phase = .connecting
        Task {
            // A task's closure doesn't infer the typed throw, so it's spelled out.
            do throws(ExtensionsModel.RepositoryFailure) {
                try await model.addRepository(address, signIn: signIn)
                dismiss()
            } catch {
                // Straight to the fields the repository asked for.
                if let asks = error.asks { signIn.kind = asks }
                phase = .failed(error.error)
            }
        }
    }
}

/// Replaces or removes how the server signs in to a repository. What's
/// saved is never sent back, so the form starts empty.
struct RepositorySignInView: View {
    let repository: ChekAPI.ExtensionRepository
    let model: ExtensionsModel
    @Environment(\.dismiss) private var dismiss
    @State private var signIn: RepositorySignIn
    @State private var phase = AddServerView.Phase.editing

    init(repository: ChekAPI.ExtensionRepository, model: ExtensionsModel) {
        self.repository = repository
        self.model = model
        _signIn = State(initialValue: RepositorySignIn(kind: repository.hasCredentials == true ? .token : .none))
    }

    /// Choosing None for a public repository changes nothing.
    private var canSave: Bool {
        phase != .connecting
            && signIn.isComplete
            && (signIn.kind != .none || repository.hasCredentials == true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Repository", value: repository.displayName)
                } footer: {
                    if repository.hasCredentials == true {
                        Text("Its saved details aren't shown. Enter new ones to replace them, or choose None to remove them.")
                    }
                }
                RepositorySignInSection(signIn: $signIn, phase: phase)
            }
            .onChange(of: signIn) { old, new in
                // Switching kind, by hand or because the repository asked,
                // keeps the message, which says what to choose; typing
                // clears it.
                if case .failed = phase, old.kind == new.kind { phase = .editing }
            }
            .navigationTitle("Sign-In Details")
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
                        Button("Save", systemImage: "checkmark", action: save)
                            .disabled(!canSave)
                    }
                }
            }
        }
        .interactiveDismissDisabled(phase == .connecting)
    }

    private func save() {
        guard canSave else { return }
        phase = .connecting
        Task {
            // A task's closure doesn't infer the typed throw, so it's spelled out.
            do throws(ExtensionsModel.RepositoryFailure) {
                try await model.setSignIn(signIn, of: repository)
                dismiss()
            } catch {
                if let asks = error.asks { signIn.kind = asks }
                phase = .failed(error.error)
            }
        }
    }
}

/// How the server signs in to a private repository: a token, a user name
/// and password, or headers of its own.
private struct RepositorySignInSection: View {
    @Binding var signIn: RepositorySignIn
    let phase: AddServerView.Phase

    var body: some View {
        Section {
            Picker("Sign In With", selection: $signIn.kind) {
                Text("None").tag(RepositorySignIn.Kind.none)
                Text("Token").tag(RepositorySignIn.Kind.token)
                Text("User Name and Password").tag(RepositorySignIn.Kind.password)
                Text("Headers").tag(RepositorySignIn.Kind.header)
            }
            switch signIn.kind {
            case .none:
                EmptyView()
            case .token:
                SecureField("Token", text: $signIn.token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            case .password:
                TextField("User Name", text: $signIn.username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $signIn.password)
                    .textContentType(.password)
            case .header:
                ForEach($signIn.headers) { $header in
                    TextField("Header Name", text: $header.name, prompt: Text(verbatim: "X-Api-Key"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Value", text: $header.value)
                }
                if signIn.headers.count > 1 {
                    Button("Remove Last Header", systemImage: "minus.circle", role: .destructive) {
                        signIn.headers.removeLast()
                    }
                }
                if signIn.headers.count < RepositorySignIn.maxHeaders {
                    Button("Add Header", systemImage: "plus.circle") {
                        signIn.headers.append(RepositorySignIn.Header())
                    }
                }
            }
        } header: {
            Text("Private Repository")
        } footer: {
            if case .failed(let error) = phase {
                FormError(error: error)
            } else {
                Text("For a private GitHub repository, use a fine-grained token that can only read its contents. For Cloudflare Access, add two headers: CF-Access-Client-Id and CF-Access-Client-Secret. The server keeps these and sends them only to the repository's own site.")
            }
        }
    }
}
