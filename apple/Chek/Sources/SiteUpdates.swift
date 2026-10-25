import Foundation
import Observation

/// Keeps the sites added to each shared library current without anyone
/// having to look: a few times a day, and whenever Sites opens, it has the
/// server read its repositories again, so newly published sites and new
/// versions show up, and installs the new versions when automatic updates
/// are on for that library, as they are unless turned off.
@MainActor
@Observable
final class SiteUpdates {
    /// Sites with a newer version waiting, by library, for libraries that
    /// don't update by themselves.
    private(set) var pending: [UUID: Int] = [:]
    /// Libraries being checked or updated now.
    private(set) var checking: Set<UUID> = []

    private let servers: ServerStore
    private let defaults: UserDefaults
    @ObservationIgnored private var lastCheck: [UUID: Date] = [:]

    /// How often a library is checked without being asked to.
    private static let interval: TimeInterval = 6 * 60 * 60

    init(servers: ServerStore, defaults: UserDefaults = .standard) {
        self.servers = servers
        self.defaults = defaults
    }

    /// Updates waiting across every library.
    var total: Int {
        pending.values.reduce(0, +)
    }

    /// Whether `account`'s sites update by themselves. On unless turned off.
    func isAutomatic(_ account: UUID) -> Bool {
        defaults.object(forKey: Self.key(account)) as? Bool ?? true
    }

    func setAutomatic(_ isOn: Bool, for account: UUID) {
        defaults.set(isOn, forKey: Self.key(account))
        if isOn {
            Task { await check(account, force: true) }
        }
    }

    /// Checks every signed-in library that hasn't been checked lately.
    func checkAll() async {
        for account in servers.accounts() where servers.state(of: account.id) == .signedIn {
            await check(account.id, force: false)
        }
    }

    /// Has the server read `account`'s repositories again, then installs
    /// the new versions or counts them, as the library's setting says.
    func check(_ account: UUID, force: Bool) async {
        guard !checking.contains(account) else { return }
        if !force, let last = lastCheck[account], Date.now.timeIntervalSince(last) < Self.interval { return }
        // The sample library can't change its sites, so it's only asked
        // what they are.
        if account == DemoMode.accountID {
            lastCheck[account] = .now
            if let installed = try? await servers.request(account, { client throws(ChekError) in
                try await client.installedExtensions()
            }) {
                SourceFormats.remember(installed, on: account)
            }
            return
        }
        checking.insert(account)
        defer { checking.remove(account) }
        lastCheck[account] = .now
        guard let repositories = try? await servers.request(account, { client throws(ChekError) in
            try await client.extensionRepositories()
        }) else { return }
        // One at a time: there are only ever a few, and each is one fetch.
        // One that can't be read keeps its last index.
        for repository in repositories {
            try? await servers.request(account) { client throws(ChekError) in
                try await client.refresh(repository: repository.id)
            }
        }
        guard let installed = try? await servers.request(account, { client throws(ChekError) in
            try await client.installedExtensions()
        }) else { return }
        SourceFormats.remember(installed, on: account)
        let outdated = installed.filter { $0.update != nil && $0.usable }
        guard isAutomatic(account) else {
            pending[account] = outdated.count
            return
        }
        var left = 0
        for site in outdated {
            do {
                _ = try await servers.request(account) { client throws(ChekError) in
                    try await client.install(site.id, from: site.repositoryId)
                }
            } catch {
                left += 1
            }
        }
        pending[account] = left
    }

    /// Installs every waiting update for `account` now.
    func updateAll(_ account: UUID) async {
        guard let installed = try? await servers.request(account, { client throws(ChekError) in
            try await client.installedExtensions()
        }) else { return }
        checking.insert(account)
        defer { checking.remove(account) }
        var left = 0
        for site in installed where site.update != nil && site.usable {
            do {
                _ = try await servers.request(account) { client throws(ChekError) in
                    try await client.install(site.id, from: site.repositoryId)
                }
            } catch {
                left += 1
            }
        }
        pending[account] = left
    }

    /// Notes what Sites just showed, so the count elsewhere agrees with it.
    func noteInstalled(_ installed: [ChekAPI.InstalledExtension], on account: UUID) {
        SourceFormats.remember(installed, on: account)
        pending[account] = isAutomatic(account) ? 0 : installed.filter { $0.update != nil && $0.usable }.count
    }

    private static func key(_ account: UUID) -> String {
        "sites.autoUpdate.\(account.uuidString)"
    }
}
