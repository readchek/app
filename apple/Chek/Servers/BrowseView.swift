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
                    ContentUnavailableView {
                        Label("No Servers", systemImage: "server.rack")
                    } description: {
                        Text("Connect a Chek server to read from it without downloading first. Your place follows you between devices.")
                    } actions: {
                        Button("Connect a Server") {
                            router.sheet = .addServer
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(accounts) { account in
                        NavigationLink(value: Route.server(account.id)) {
                            ServerRow(account: account)
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
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                Text(servers.state(of: account.id) == .signedOut ? "Signed out" : account.userName)
                    .font(.subheadline)
                    .foregroundStyle(servers.state(of: account.id) == .signedOut ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            }
        } icon: {
            Image(systemName: "server.rack")
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
