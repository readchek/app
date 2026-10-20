import SwiftUI

/// The tabs, and everything presented over them.
struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var library
    @Namespace private var readerTransition

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Reading Now", systemImage: "book", value: AppTab.home) {
                HomeView()
            }
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                LibraryView()
            }
            Tab("Browse", systemImage: "server.rack", value: AppTab.browse) {
                BrowseView()
            }
            Tab(value: AppTab.search, role: .search) {
                SearchView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .nowReadingAccessory()
        .environment(\.readerTransition, readerTransition)
        .fullScreenCover(item: $router.reading) { item in
            ReaderHost(item: item)
                .navigationTransition(.zoom(sourceID: item.ref, in: readerTransition))
        }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .settings:
                SettingsView()
            case .addServer:
                AddServerView()
            case .signIn(let account):
                SignInView(account: account)
            }
        }
        .onOpenURL { url in
            // Files opened from other apps are added to the library.
            guard url.isFileURL else { return }
            router.tab = .library
            library.importBooks(from: [url])
        }
        .fileImporter(isPresented: $router.isImportingFiles, allowedContentTypes: BookImporter.contentTypes, allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                router.tab = .library
                library.importBooks(from: urls)
            }
        }
        .importFailureAlert()
        .openingFailureAlert()
        .syncTriggers()
    }
}

/// Starts the reader with the current reading settings. Split out so the
/// root view doesn't depend on them.
private struct ReaderHost: View {
    let item: ReadingItem
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        ReaderScreen(item: item, preferences: settings.preferences(for: item.settingsKey))
    }
}

extension EnvironmentValues {
    /// The namespace covers zoom out of when a publication opens. Nil
    /// outside the app's root, where there's nothing to zoom to.
    @Entry var readerTransition: Namespace.ID?
}

extension View {
    /// Marks this view as where `ref` zooms out of when it opens.
    func readerTransitionSource(_ ref: PublicationRef) -> some View {
        modifier(ReaderTransitionSource(ref: ref))
    }
}

private struct ReaderTransitionSource: ViewModifier {
    let ref: PublicationRef
    @Environment(\.readerTransition) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: ref, in: namespace)
        } else {
            content
        }
    }
}

extension View {
    /// Explains why a server publication couldn't open.
    fileprivate func openingFailureAlert() -> some View {
        modifier(OpeningFailureAlert())
    }
}

/// Split out so the root view doesn't redraw when opening fails.
private struct OpeningFailureAlert: ViewModifier {
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content.alert(
            router.openingFailure?.error.title ?? "",
            isPresented: Binding { router.openingFailure != nil } set: { if !$0 { router.openingFailure = nil } },
            presenting: router.openingFailure
        ) { failure in
            if let account = failure.signIn {
                Button("Sign In") { router.sheet = .signIn(account) }
                Button("Not Now", role: .cancel) { router.dropPendingOpen() }
            } else {
                Button("OK") {}
            }
        } message: { failure in
            if let message = failure.error.message {
                Text(message)
            }
        }
    }
}
