import SwiftData
import SwiftUI

/// The libraries shared with you, and everything in them.
struct BrowseView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \ServerAccount.sortIndex) private var accounts: [ServerAccount]
    @Environment(ServerStore.self) private var servers
    @State private var editing: ServerEdit?

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.browsePath) {
            Group {
                if accounts.isEmpty {
                    EmptyState(
                        "Nothing Shared Yet",
                        systemImage: "building.columns",
                        description: Text("When someone shares their Chek library with you, add it here to read from it on all your devices.")
                    ) {
                        Button("Add Shared Library") {
                            router.sheet = .addServer
                        }
                    } secondary: {
                        TryDemoButton()
                    }
                } else {
                    List {
                        ForEach(accounts) { account in
                            NavigationLink(value: Route.server(account.id)) {
                                ServerRow(account: account)
                            }
                            .contextMenu {
                                ServerActions(account: account, editing: $editing)
                            }
                            // Not a destructive role: that removes the row at
                            // once, before you've confirmed, and the list then
                            // disagrees with the servers it shows.
                            .swipeActions(allowsFullSwipe: false) {
                                if account.id == DemoMode.accountID {
                                    Button("Close", systemImage: "xmark") {
                                        Task { await servers.endDemo() }
                                    }
                                    .tint(.red)
                                } else {
                                    Button("Remove", systemImage: "trash") {
                                        editing = .remove(account)
                                    }
                                    .tint(.red)
                                    Button("Rename", systemImage: "pencil") {
                                        editing = .rename(account)
                                    }
                                    .tint(.gray)
                                }
                            }
                        }
                        .onMove(perform: move)
                    }
                }
            }
            .demoBanner()
            .navigationTitle("Shared")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Shared Library", systemImage: "plus") {
                        router.sheet = .addServer
                    }
                }
                if accounts.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                }
            }
            .routeDestinations()
            .serverEditing($editing)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = accounts
        ordered.move(fromOffsets: source, toOffset: destination)
        servers.reorder(ordered)
    }
}

/// A server's name with your account under it, or that you're signed out.
/// Browse and Settings both list servers with it, so they always agree.
struct ServerRow: View {
    let account: ServerAccount
    @Environment(ServerStore.self) private var servers

    var body: some View {
        let isDemo = account.id == DemoMode.accountID
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                // The demo is a temporary account, which its row says
                // rather than naming a user nobody signed in as.
                Text(isDemo ? "Until you close Chek" : servers.state(of: account.id) == .signedOut ? "Sign in again to read" : account.userName)
                    .font(.subheadline)
                    .foregroundStyle(servers.state(of: account.id) == .signedOut ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            }
        } icon: {
            Image(systemName: isDemo ? "sparkles" : "building.columns")
        }
    }
}

extension View {
    /// The screens any tab can push for a server.
    func routeDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            Group {
                switch route {
                case .server(let account):
                    ServerHomeView(account: account)
                case .serverLibrary(let account, let library):
                    ServerLibraryView(account: account, library: library)
                case .series(let account, let series, let title):
                    SeriesView(account: account, seriesID: series, title: title)
                case .source(let account, let source):
                    SourceView(account: account, source: source)
                case .sourceSeries(let account, let source, let series, let title):
                    SourceSeriesView(account: account, source: source, seriesID: series, title: title)
                case .extensions(let account):
                    ExtensionsView(account: account)
                }
            }
            // On every pushed screen too, so the demo is never mistaken
            // for the real thing a few taps in.
            .demoBanner()
        }
    }
}

/// A change to a server that needs a question answered first.
enum ServerEdit: Identifiable {
    case rename(ServerAccount)
    case remove(ServerAccount)

    var id: String {
        switch self {
        case .rename(let account): "rename-\(account.id)"
        case .remove(let account): "remove-\(account.id)"
        }
    }
}

/// Rename, sign in or out, and remove: what you can do to a server, shared
/// by its row's menu and its own screen's toolbar.
struct ServerActions: View {
    let account: ServerAccount
    @Binding var editing: ServerEdit?
    @Environment(ServerStore.self) private var servers
    @Environment(AppRouter.self) private var router

    var body: some View {
        if account.id == DemoMode.accountID {
            Button("Close the Sample Library", systemImage: "xmark", role: .destructive) {
                Task { await servers.endDemo() }
            }
        } else {
            Button("Rename", systemImage: "pencil") {
                editing = .rename(account)
            }
            if servers.state(of: account.id) == .signedIn {
                Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") {
                    Task { await servers.signOut(account) }
                }
            } else {
                Button("Sign In", systemImage: "person.crop.circle") {
                    router.sheet = .signIn(account.id)
                }
            }
            Divider()
            Button("Remove", systemImage: "trash", role: .destructive) {
                editing = .remove(account)
            }
        }
    }
}

extension View {
    /// The rename prompt and the removal confirmation for ``ServerEdit``.
    func serverEditing(_ editing: Binding<ServerEdit?>) -> some View {
        modifier(ServerEditing(editing: editing))
    }
}

private struct ServerEditing: ViewModifier {
    @Binding var editing: ServerEdit?
    @Environment(ServerStore.self) private var servers
    @Environment(AppRouter.self) private var router
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert("Rename", isPresented: isRenaming) {
                TextField("Name", text: $name)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    if case .rename(let account) = editing {
                        servers.rename(account, to: name)
                    }
                }
            } message: {
                Text("Only you see this name.")
            }
            .confirmationDialog(removalTitle, isPresented: isRemoving, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    guard case .remove(let account) = editing else { return }
                    let id = account.id
                    if router.browsePath.first == .server(id) {
                        router.browsePath = []
                    }
                    router.serverRemoved(account.id)
                    Task { await servers.remove(account) }
                }
            } message: {
                Text("It's removed from this device along with its downloads. Your places are kept, so adding it again picks up where you left off.")
            }
            .onChange(of: editing?.id) {
                if case .rename(let account) = editing {
                    name = account.name
                }
            }
    }

    private var isRenaming: Binding<Bool> {
        Binding {
            if case .rename = editing { true } else { false }
        } set: {
            if !$0 { editing = nil }
        }
    }

    private var isRemoving: Binding<Bool> {
        Binding {
            if case .remove = editing { true } else { false }
        } set: {
            if !$0 { editing = nil }
        }
    }

    private var removalTitle: String {
        if case .remove(let account) = editing {
            String(localized: "Remove \(account.name)?")
        } else {
            ""
        }
    }
}
