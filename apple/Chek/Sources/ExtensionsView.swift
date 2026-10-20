import SwiftUI

/// The extensions a server's repositories offer, to install, update and
/// remove. Each one installed is a source on that server.
struct ExtensionsView: View {
    let account: UUID
    @Environment(ServerStore.self) private var servers
    @State private var model: ExtensionsModel?

    var body: some View {
        Group {
            switch model?.state ?? .idle {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.large)
            case .failed(let error):
                ContentUnavailableView {
                    Label(error.title, systemImage: "wifi.exclamationmark")
                } description: {
                    if let message = error.message {
                        Text(message)
                    }
                } actions: {
                    Button("Try Again") {
                        Task { await model?.load() }
                    }
                    .buttonStyle(.bordered)
                }
            case .loaded(let content):
                if let model {
                    ExtensionsList(content: content, model: model)
                }
            }
        }
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: account) {
            let model = model ?? ExtensionsModel(account: account, servers: servers)
            self.model = model
            await model.load()
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
    }

    private(set) var state: LoadState<Content> = .idle
    /// Extensions being installed, updated or removed, by id.
    private(set) var changing: Set<String> = []
    /// Why the last change failed, until it's been shown.
    var failure: DisplayError?

    private let account: UUID
    private let servers: ServerStore

    init(account: UUID, servers: ServerStore) {
        self.account = account
        self.servers = servers
    }

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
                    return try await Content(available: available, installed: installed, repositories: repositories)
                } catch let error as ChekError {
                    throw error
                } catch {
                    throw .invalidResponse
                }
            }
            state = .loaded(content)
        } catch .notFound {
            state = .failed(DisplayError(
                title: String(localized: "This server doesn't have sources yet."),
                message: String(localized: "Update the Chek server to add extensions.")
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
        } catch .server(status: 403, _) {
            failure = DisplayError(title: String(localized: "The server's admin hasn't allowed this repository."))
        } catch .server(status: 422, _) {
            failure = DisplayError(title: String(localized: "This extension couldn't be installed."), message: String(localized: "It doesn't match what its repository lists. Try again after the repository updates."))
        } catch .server(status: 502, _) {
            failure = DisplayError(title: String(localized: "The repository couldn't be reached."), message: String(localized: "Try again in a moment."))
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

    var body: some View {
        let installed = Dictionary(content.installed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Installed from a repository that's gone or no longer allowed, so
        // no listing shows it; it still needs a way to be removed.
        let offered = Set(content.available.map(\.id))
        let orphans = content.installed.filter { !offered.contains($0.id) }
        List {
            if !orphans.isEmpty {
                Section {
                    ForEach(orphans) { item in
                        OrphanExtensionRow(item: item, isChanging: model.changing.contains(item.id), model: model)
                    }
                } header: {
                    Text("Installed")
                } footer: {
                    Text("No repository the server can read offers these now, so they can't be updated, only removed.")
                }
            }
            if content.available.isEmpty, orphans.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Extensions",
                        systemImage: "puzzlepiece.extension",
                        description: Text("The server's repositories don't offer any yet.")
                    )
                }
            } else if !content.available.isEmpty {
                Section {
                    ForEach(content.available, id: \.listingID) { item in
                        ExtensionRow(item: item, installed: installed[item.id], isChanging: model.changing.contains(item.id), model: model)
                    }
                } footer: {
                    Text("Sources run on the server, which reaches only the sites each lists, so reading from them works the same on all your devices.")
                }
            }
            if !content.repositories.isEmpty {
                Section("Repositories") {
                    ForEach(content.repositories) { repository in
                        RepositoryRow(repository: repository)
                    }
                }
            }
        }
        .refreshable {
            await model.refreshRepositories()
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
                        .accessibilityLabel(Text("Installed"))
                }
            } else {
                Button("Get") {
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

    private var details: String {
        let version: String
        if let installed, installed.version != item.version {
            version = String(localized: "Version \(installed.version), \(item.version) available")
        } else {
            version = String(localized: "Version \(item.version)")
        }
        var parts = [version]
        if let site = item.sites.first(where: { !$0.hasPrefix("*") }) ?? item.sites.first {
            parts.append(site)
        }
        if item.capabilities.contains("browser") {
            parts.append(String(localized: "Uses the server's browser"))
        }
        return parts.joined(separator: " · ")
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
                Text(item.usable ? String(localized: "Version \(item.version)") : String(localized: "Version \(item.version) · Not allowed on this server"))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(repository.name ?? URL(string: repository.url)?.host() ?? repository.url)
            if let error = repository.fetchError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            } else if repository.fetchedAt == nil {
                Text("Not read yet. Pull down to check it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(repository.allowListed ? "^[\(repository.extensionCount) extension](inflect: true) · Allowed by the admin" : "^[\(repository.extensionCount) extension](inflect: true) · Yours")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
