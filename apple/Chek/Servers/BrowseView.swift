import SwiftData
import SwiftUI

/// The servers you've connected, and everything on them.
struct BrowseView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \ServerAccount.sortIndex) private var accounts: [ServerAccount]

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.browsePath) {
            Group {
                if accounts.isEmpty {
                    NoServersView()
                } else {
                    List {
                        Section {
                            ForEach(accounts) { account in
                                NavigationLink(value: Route.server(account.id)) {
                                    ServerRow(account: account)
                                }
                            }
                        } footer: {
                            Text("Books you open from a server stream from it, and your place syncs with your other devices.")
                        }
                    }
                }
            }
            .navigationTitle("Browse")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Connect a Server", systemImage: "plus") {
                        router.sheet = .addServer
                    }
                }
            }
            .routeDestinations()
        }
    }
}

private struct ServerRow: View {
    let account: ServerAccount
    @Environment(ServerStore.self) private var servers

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.tint(.accentColor.opacity(0.15)), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.headline)
                Text(account.userName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if servers.state(of: account.id) == .signedOut {
                Text("Signed Out")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct NoServersView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ContentUnavailableView {
            Label("Connect a Server", systemImage: "server.rack")
        } description: {
            Text("Read from your Chek server without downloading first. Your place in each book follows you between devices.")
        } actions: {
            Button("Connect a Server") {
                router.sheet = .addServer
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
    }
}

extension View {
    /// The screens any tab can push for a server.
    func routeDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .server(let account):
                ServerHomeView(account: account)
            case .serverLibrary(let account, let library):
                ServerLibraryView(account: account, library: library)
            case .series(let account, let series, let title):
                SeriesView(account: account, seriesID: series, title: title)
            }
        }
    }
}
