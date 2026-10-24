import SwiftUI

/// The extensions a server's repositories offer, to install, update and
/// remove. Each one installed is a source on that server.
struct ExtensionsView: View {
    let account: UUID
    @Environment(ServerStore.self) private var servers
    @Environment(SiteUpdates.self) private var siteUpdates
    @State private var model: ExtensionsModel?

    var body: some View {
        Group {
            switch model?.state ?? .idle {
            case .idle, .loading:
                LoadingState()
            case .failed(let error):
                FailureState(error: error) {
                    await model?.load()
                }
            case .loaded(let content):
                if let model {
                    ExtensionsList(content: content, model: model, isChecking: siteUpdates.checking.contains(account))
                }
            }
        }
        .navigationTitle("Sites")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: account) {
            let model = model ?? ExtensionsModel(account: account, servers: servers)
            self.model = model
            await model.load()
            // What the list showed may be old: the repositories are read
            // again, new versions installed when the library updates by
            // itself, and the list shown again.
            await siteUpdates.check(account, force: true)
            await model.load()
            if let installed = model.state.value?.installed {
                siteUpdates.noteInstalled(installed, on: account)
            }
        }
        .alert(
            model?.failure?.title ?? "",
            isPresented: Binding { model?.failure != nil } set: { if !$0 { model?.failure = nil } }
        ) {
            Button("OK") {}
        } message: {
            if let message = model?.failure?.message {
                Text(message)
            }
        }
    }
}

/// Owns what a server's repositories offer and every install change, one
/// at a time per extension.
@MainActor
@Observable
final class ExtensionsModel {
    struct Content: Equatable {
        var available: [ChekAPI.AvailableExtension]
        var installed: [ChekAPI.InstalledExtension]
        var repositories: [ChekAPI.ExtensionRepository]
        /// Nil from a server older than its settings.
        var settings: ChekAPI.ServerSettings?
        var isAdmin: Bool

        /// Admins add to the list everyone sees; others add their own
        /// once the admin allows it.
        var canAddRepositories: Bool {
            isAdmin || settings?.allowAnyRepository == true
        }

        /// Admins manage every repository; others only the ones they added.
        func canManage(_ repository: ChekAPI.ExtensionRepository) -> Bool {
            isAdmin || !repository.allowListed
        }
    }

    private(set) var state: LoadState<Content> = .idle
    /// Extensions being installed, updated or removed, by id.
    private(set) var changing: Set<String> = []
    /// Repositories being removed, by id.
    private(set) var removingRepositories: Set<Int64> = []
    private(set) var isSavingSettings = false
    /// Why the last change failed, until it's been shown.
    var failure: DisplayError?

    private let account: UUID
    private let servers: ServerStore

    init(account: UUID, servers: ServerStore) {
        self.account = account
        self.servers = servers
    }

    /// The shared demo account can't change anything, so it isn't offered.
    var isDemo: Bool { account == DemoMode.accountID }

    func load() async {
        if state.value == nil {
            state = .loading
        }
        do {
            let content = try await servers.request(account) { client throws(ChekError) in
                // `async let` loses the error type, so it's restored for the
                // store to see sign-outs.
                do {
                    async let available = client.availableExtensions()
                    async let installed = client.installedExtensions()
                    async let repositories = client.extensionRepositories()
                    async let user = client.currentUser()
                    // Missing settings only hide the admin's switch.
                    async let settings = try? client.settings()
                    return try await Content(available: available, installed: installed, repositories: repositories, settings: settings, isAdmin: user.isAdmin)
                } catch let error as ChekError {
                    throw error
                } catch {
                    throw .invalidResponse
                }
            }
            state = .loaded(content)
        } catch .notFound {
            state = .failed(DisplayError(
                title: String(localized: "Sites Not Available"),
                message: String(localized: "This library needs a newer version of Chek before sites can be added. Ask its administrator.")
            ))
        } catch {
            if state.value == nil {
                state = .failed(DisplayError(error))
            }
        }
    }

    /// Has the server read every repository's index again, then reloads,
    /// so extensions just published show up.
    func refreshRepositories() async {
        // One at a time: there are only ever a few, and each is one fetch.
        for repository in state.value?.repositories ?? [] {
            // A repository that can't be read keeps its last index, and its
            // row says why.
            try? await servers.request(account) { client throws(ChekError) in
                try await client.refresh(repository: repository.id)
            }
        }
        await load()
    }

    /// Why a repository couldn't be added or signed in to, and the sign-in
    /// it asked for, so the form can switch to it.
    struct RepositoryFailure: Error {
        var error: DisplayError
        var asks: RepositorySignIn.Kind?
    }

    /// Adds a repository, signing in to it when it's private. Throws why
    /// it couldn't, for the form to show next to what was typed.
    func addRepository(_ address: String, signIn: RepositorySignIn) async throws(RepositoryFailure) {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let credentials = signIn.credentials
        do {
            _ = try await servers.request(account) { client throws(ChekError) in
                try await client.addRepository(address, credentials: credentials)
            }
        } catch {
            throw Self.repositoryFailure(error)
        }
        await load()
    }

    /// Replaces a repository's sign-in details, or removes them for `.none`.
    func setSignIn(_ signIn: RepositorySignIn, of repository: ChekAPI.ExtensionRepository) async throws(RepositoryFailure) {
        let credentials = signIn.credentials
        do {
            _ = try await servers.request(account) { client throws(ChekError) in
                try await client.setCredentials(credentials, of: repository.id)
            }
        } catch {
            throw Self.repositoryFailure(error)
        }
        await load()
    }

    /// Removes a repository, and with it every extension installed from it.
    func remove(_ repository: ChekAPI.ExtensionRepository) async {
        guard !removingRepositories.contains(repository.id) else { return }
        removingRepositories.insert(repository.id)
        defer { removingRepositories.remove(repository.id) }
        do {
            try await servers.request(account) { client throws(ChekError) in
                try await client.removeRepository(repository.id)
            }
        } catch {
            failure = Self.repositoryFailure(error).error
        }
        await load()
    }

    func setAllowAnyRepository(_ allow: Bool) async {
        guard !isSavingSettings else { return }
        isSavingSettings = true
        defer { isSavingSettings = false }
        // The switch moves at once; the reload below sets it back if the
        // server didn't take it.
        if case .loaded(var content) = state {
            content.settings?.allowAnyRepository = allow
            state = .loaded(content)
        }
        do {
            _ = try await servers.request(account) { client throws(ChekError) in
                try await client.saveSettings(ChekAPI.ServerSettings(allowAnyRepository: allow))
            }
        } catch {
            failure = DisplayError(error)
        }
        await load()
    }

    static func repositoryFailure(_ error: ChekError) -> RepositoryFailure {
        let isPrivate = String(localized: "Private Repository")
        return switch error {
        case .server(status: 422, "repository_needs_token"):
            RepositoryFailure(error: DisplayError(title: isPrivate, message: String(localized: "Sign in with a token. For a private GitHub repository, use a fine-grained token that can read its contents.")), asks: .token)
        case .server(status: 422, "repository_needs_password"):
            RepositoryFailure(error: DisplayError(title: isPrivate, message: String(localized: "Sign in with its user name and password.")), asks: .password)
        case .server(status: 422, "repository_needs_credentials"):
            RepositoryFailure(error: DisplayError(title: isPrivate, message: String(localized: "Sign in with the headers its host asks for, such as a Cloudflare Access service token's ID and secret.")), asks: .header)
        case .server(status: 422, "repository_credentials_refused"):
            RepositoryFailure(error: DisplayError(title: String(localized: "Sign-In Details Refused"), message: String(localized: "Check the details and that they still have access to the repository.")))
        default:
            RepositoryFailure(error: repositoryError(error))
        }
    }

    private static func repositoryError(_ error: ChekError) -> DisplayError {
        switch error {
        case .server(status: 403, "demo_account"):
            DisplayError(title: String(localized: "Sample Library Can't Be Changed"), message: String(localized: "Add a shared library of your own to add repositories."))
        case .server(status: 403, "repository_not_allowed"):
            DisplayError(title: String(localized: "Only the Administrator Can Add Repositories"), message: String(localized: "Ask them to turn on “Anyone Can Add Repositories”."))
        case .server(status: 403, _):
            DisplayError(title: String(localized: "Only the Administrator Can Change This Repository"))
        case .server(status: 400, _):
            DisplayError(title: String(localized: "Check the Address and Sign-In Details"), message: String(localized: "Repositories use HTTPS. A password goes in the sign-in details, not the address, and a token, user name, or header name can't be empty."))
        case .server(status: 409, _):
            DisplayError(title: String(localized: "Repository Already Added"))
        case .server(status: 502, _):
            DisplayError(title: String(localized: "Couldn't Read Repository"), message: String(localized: "Check the address and that it contains an index.json file."))
        default:
            DisplayError(error)
        }
    }

    /// Installs `item`, or updates it when it's installed already.
    func install(_ item: ChekAPI.AvailableExtension) async {
        await change(item.id) { client throws(ChekError) in
            _ = try await client.install(item.id, from: item.repositoryId)
        }
    }

    func uninstall(_ id: String) async {
        await change(id) { client throws(ChekError) in
            try await client.uninstall(id)
        }
    }

    private func change(_ id: String, _ operation: @escaping (ChekClient) async throws(ChekError) -> Void) async {
        guard !changing.contains(id) else { return }
        changing.insert(id)
        defer { changing.remove(id) }
        do {
            try await servers.request(account, operation)
        } catch .server(status: 403, "demo_account") {
            failure = DisplayError(title: String(localized: "Sites Can't Be Added to the Sample Library"))
        } catch .server(status: 403, _) {
            failure = DisplayError(title: String(localized: "Site Turned Off"))
        } catch .server(status: 422, let code?) where code.hasPrefix("repository_") {
            failure = DisplayError(title: String(localized: "Repository Refused the Download"), message: String(localized: "Check its sign-in details under Advanced."))
        } catch .server(status: 422, _), .server(status: 502, _) {
            // A bad download and a bad answer from the repository look the
            // same from here: not now, maybe later.
            failure = DisplayError(title: String(localized: "Couldn't Add Site"), message: String(localized: "Try again later."))
        } catch {
            failure = DisplayError(error)
        }
        // The server's answer is the truth about what's installed now.
        await load()
    }
}

private struct ExtensionsList: View {
    let content: ExtensionsModel.Content
    let model: ExtensionsModel
    var isChecking = false

    var body: some View {
        let installed = Dictionary(content.installed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Installed from a repository that's gone or no longer allowed, so
        // no listing shows it; it still needs a way to be removed.
        let offered = Set(content.available.map(\.id))
        let orphans = content.installed.filter { !offered.contains($0.id) }
        List {
            if isChecking {
                Label {
                    Text("Checking for new sites and updates…")
                        .foregroundStyle(.secondary)
                } icon: {
                    ProgressView()
                }
            }
            if content.available.isEmpty, orphans.isEmpty {
                Section {
                    EmptyState("The library's administrator hasn't added any sites yet.", systemImage: "globe")
                }
            } else if !content.available.isEmpty {
                Section {
                    ForEach(content.available, id: \.listingID) { item in
                        ExtensionRow(item: item, installed: installed[item.id], isChanging: model.changing.contains(item.id), model: model)
                    }
                } footer: {
                    Text("Sites you add appear on Home and in Search on all your devices.")
                }
            }
            if !orphans.isEmpty {
                Section {
                    ForEach(orphans) { item in
                        OrphanExtensionRow(item: item, isChanging: model.changing.contains(item.id), model: model)
                    }
                } header: {
                    Text("No Longer Offered")
                } footer: {
                    Text("These sites still work but no longer receive updates.")
                }
            }
            // Where sites come from is for whoever runs the library, so
            // it's a screen of its own rather than part of this list.
            if !model.isDemo, content.canAddRepositories || !content.repositories.isEmpty {
                Section {
                    NavigationLink {
                        SiteSourcesView(content: content, model: model)
                    } label: {
                        Text("Advanced")
                    }
                } footer: {
                    Text("Repositories and settings for the library's administrator.")
                }
            }
        }
        .refreshable {
            await model.refreshRepositories()
        }
    }
}

/// Where a library's sites come from: the repositories it reads, and for
/// its admin whether everyone may add their own. Kept off the main list,
/// since only whoever runs the library needs it.
private struct SiteSourcesView: View {
    let snapshot: ExtensionsModel.Content
    let model: ExtensionsModel
    @State private var sheet: RepositorySheet?
    @State private var removing: ChekAPI.ExtensionRepository?

    init(content: ExtensionsModel.Content, model: ExtensionsModel) {
        snapshot = content
        self.model = model
    }

    /// The latest the model has, so adding a repository shows here at once.
    private var content: ExtensionsModel.Content {
        model.state.value ?? snapshot
    }

    var body: some View {
        List {
            repositories
            if content.isAdmin, let settings = content.settings {
                Section {
                    Toggle("Anyone Can Add Repositories", isOn: Binding {
                        settings.allowAnyRepository
                    } set: { allow in
                        Task { await model.setAllowAnyRepository(allow) }
                    })
                    .disabled(model.isSavingSettings)
                } footer: {
                    Text("Lets everyone with access to this library add repositories that only they can see.")
                }
            }
        }
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await model.refreshRepositories()
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .add:
                AddRepositoryView(model: model, isShared: content.isAdmin)
            case .signIn(let repository):
                RepositorySignInView(repository: repository, model: model)
            }
        }
        .confirmationDialog(
            Text("Remove “\(removing?.displayName ?? "")”?"),
            isPresented: Binding { removing != nil } set: { if !$0 { removing = nil } },
            titleVisibility: .visible,
            presenting: removing
        ) { repository in
            Button("Remove Repository", role: .destructive) {
                Task { await model.remove(repository) }
            }
        } message: { repository in
            Text(repository.allowListed ? "Sites from it are removed for everyone." : "Sites from it are removed too.")
        }
    }

    @ViewBuilder private var repositories: some View {
        let canAdd = !model.isDemo && content.canAddRepositories
        if !content.repositories.isEmpty || canAdd {
            Section {
                ForEach(content.repositories) { repository in
                    let canManage = !model.isDemo && content.canManage(repository)
                    RepositoryRow(repository: repository, isRemoving: model.removingRepositories.contains(repository.id))
                        .swipeActions(allowsFullSwipe: false) {
                            if canManage {
                                Button("Remove", systemImage: "trash") {
                                    removing = repository
                                }
                                .tint(.red)
                                Button("Sign-In Details", systemImage: "key") {
                                    sheet = .signIn(repository)
                                }
                            }
                        }
                        .contextMenu {
                            if canManage {
                                Button("Sign-In Details", systemImage: "key") {
                                    sheet = .signIn(repository)
                                }
                                Button("Remove…", systemImage: "trash", role: .destructive) {
                                    removing = repository
                                }
                            }
                        }
                }
                if canAdd {
                    Button("Add Repository", systemImage: "plus") {
                        sheet = .add
                    }
                }
            } header: {
                Text("Repositories")
            } footer: {
                if canAdd {
                    Text(content.isAdmin ? "Repositories you add are available to everyone with access to this library." : "Repositories you add are visible only to you.")
                }
            }
        }
    }
}

/// The forms the repositories section opens.
private enum RepositorySheet: Identifiable {
    case add
    case signIn(ChekAPI.ExtensionRepository)

    var id: String {
        switch self {
        case .add: "add"
        case .signIn(let repository): "sign-in/\(repository.id)"
        }
    }
}

/// An extension's name and the sites it reaches, with the button that
/// installs, updates or removes it.
private struct ExtensionRow: View {
    let item: ChekAPI.AvailableExtension
    let installed: ChekAPI.InstalledExtension?
    let isChanging: Bool
    let model: ExtensionsModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if isChanging {
                ProgressView()
            } else if let installed {
                if installed.version != item.version {
                    Button("Update") {
                        Task { await model.install(item) }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                } else {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Added"))
                }
            } else {
                Button("Add") {
                    Task { await model.install(item) }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
        .swipeActions(allowsFullSwipe: false) {
            if installed != nil {
                Button("Remove", systemImage: "trash") {
                    Task { await model.uninstall(item.id) }
                }
                .tint(.red)
            }
        }
        .contextMenu {
            if installed != nil {
                Button("Remove", systemImage: "trash", role: .destructive) {
                    Task { await model.uninstall(item.id) }
                }
            }
        }
    }

    /// The site it reads from, which is what people know it by.
    private var details: String {
        let site = item.sites.first(where: { !$0.hasPrefix("*") }) ?? item.sites.first
        if let installed, installed.version != item.version {
            return [site, String(localized: "Update Available")].compactMap(\.self).joined(separator: " · ")
        }
        return site ?? ""
    }
}

/// An installed extension no repository offers any more.
private struct OrphanExtensionRow: View {
    let item: ChekAPI.InstalledExtension
    let isChanging: Bool
    let model: ExtensionsModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text(item.usable ? String(localized: "No Longer Updated") : String(localized: "Turned Off"))
                    .font(.caption)
                    .foregroundStyle(item.usable ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
            }
            Spacer(minLength: 8)
            if isChanging {
                ProgressView()
            } else {
                Button("Remove", role: .destructive) {
                    Task { await model.uninstall(item.id) }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
    }
}

/// Where extensions come from, and why one can't be read.
private struct RepositoryRow: View {
    let repository: ChekAPI.ExtensionRepository
    let isRemoving: Bool

    var body: some View {
        HStack(spacing: 12) {
            details
            Spacer(minLength: 8)
            if isRemoving {
                ProgressView()
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(repository.displayName)
                if repository.hasCredentials == true {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Private"))
                }
            }
            if let error = repository.fetchError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            } else if repository.fetchedAt == nil {
                Text("Not checked yet. Pull down to refresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(repository.allowListed ? "^[\(repository.extensionCount) site](inflect: true) · Added by the administrator" : "^[\(repository.extensionCount) site](inflect: true) · Added by you")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

nonisolated extension ChekAPI.ExtensionRepository {
    /// What the repository calls itself, else its site, or `owner/repo`
    /// for one read from GitHub.
    var displayName: String {
        if let name { return name }
        guard let address = URL(string: url), let host = address.host() else { return url }
        let path = address.pathComponents.filter { $0 != "/" }
        if host == "raw.githubusercontent.com", path.count >= 2 {
            return "\(path[0])/\(path[1])"
        }
        return host
    }
}
