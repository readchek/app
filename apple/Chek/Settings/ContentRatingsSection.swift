import SwiftUI

/// Which series a shared library's search and sites show, by how mature
/// their source rates them. The choice is kept by the library, so it holds
/// on every device you read it on.
///
/// The app only narrows the choice. Mature series are turned on in the Chek
/// web app, after confirming your age there, as App Review Guideline 1.2 asks
/// of adult content from a web service; this section links to it and shows
/// what was chosen.
struct ContentRatingsSection: View {
    let account: ServerAccount
    @Environment(ServerStore.self) private var servers
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase = Phase.loading
    /// Why the last change, or opening the web app, didn't work, until the
    /// next try.
    @State private var failure: DisplayError?
    @State private var isOpeningWeb = false

    typealias Rating = ChekAPI.ContentRating

    enum Phase: Equatable {
        case loading
        case loaded(Set<Rating>)
        case saving(Set<Rating>)
        case failed(DisplayError)
    }

    /// The common choices, each a set of ratings; anything else is Custom.
    enum Preset: CaseIterable, Hashable {
        case everyone, teen, mature, custom

        var ratings: Set<Rating>? {
            switch self {
            case .everyone: [.safe]
            case .teen: [.safe, .suggestive]
            case .mature: Set(Rating.allCases)
            case .custom: nil
            }
        }

        var title: LocalizedStringResource {
            switch self {
            case .everyone: "Everyone"
            case .teen: "Teen"
            case .mature: "Mature"
            case .custom: "Custom"
            }
        }

        init(_ ratings: Set<Rating>) {
            self = Self.allCases.first { $0.ratings == ratings } ?? .custom
        }
    }

    /// The Chek web app's content settings, at app.chek.page.
    private static let webSettings = URL(string: "https://app.chek.page/settings/content")!

    private var isDemo: Bool { account.id == DemoMode.accountID }

    /// A page served over https can't reach a server on plain http, so the
    /// web app works only with https servers.
    private var webReachable: Bool { account.baseURL.scheme == "https" }

    var body: some View {
        Section {
            switch phase {
            case .loading:
                LabeledContent("Show") {
                    ProgressView()
                }
            case .failed:
                LabeledContent("Show") {
                    Button("Try Again") {
                        Task { await load() }
                    }
                }
            case .loaded(let ratings), .saving(let ratings):
                let current = Preset(ratings)
                Picker("Show", selection: Binding(
                    get: { current },
                    set: { preset in
                        // Mature and Custom are only listed while they're
                        // what the web app chose, so picking one changes
                        // nothing.
                        if preset != current, preset == .everyone || preset == .teen, let set = preset.ratings {
                            save(set)
                        }
                    }
                )) {
                    Text(Preset.everyone.title).tag(Preset.everyone)
                    Text(Preset.teen.title).tag(Preset.teen)
                    if current == .mature || current == .custom {
                        Text(current.title).tag(current)
                    }
                }
                .disabled(isDemo || isSaving)
            }
            Button {
                Task { await openWeb() }
            } label: {
                Label("Content Settings on the Web", systemImage: "safari")
            }
            .disabled(!webReachable || isOpeningWeb)
        } header: {
            Text("Content")
        } footer: {
            if case .failed(let error) = phase {
                FormError(error: error)
            } else if let failure {
                FormError(error: failure)
            } else {
                Text(footer)
            }
        }
        .task(id: account.id) {
            await load()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Coming back from the web app, show what was chosen there.
            if newPhase == .active {
                Task { await load() }
            }
        }
    }

    private var footer: LocalizedStringResource {
        if isDemo {
            return "The sample library shows safe and suggestive series."
        }
        if case .loaded(let ratings) = phase, ratings.contains(where: \.isMature) {
            return "Mature series are on, chosen on the web. Choose Everyone or Teen to turn them off. Applies to search and sites in this library, on all your devices."
        }
        if !webReachable {
            return "Applies to search and sites in this library, on all your devices. Mature series can be turned on from the web only when the server has an https address."
        }
        return "Applies to search and sites in this library, on all your devices. Mature series, for adults only, can be turned on from the web."
    }

    private var isSaving: Bool {
        if case .saving = phase { true } else { false }
    }

    private func load() async {
        let before: Set<Rating>? = if case .loaded(let ratings) = phase { ratings } else { nil }
        if before == nil {
            phase = .loading
        }
        let id = account.id
        do {
            let ratings = Set(try await servers.request(id) { client throws(ChekError) in
                try await client.contentRatings()
            })
            phase = .loaded(ratings)
            // Changed on the web: search shouldn't answer from before.
            if let before, before != ratings {
                servers.contentRatingsChanged(on: id)
            }
        } catch {
            if before == nil {
                phase = .failed(DisplayError(error))
            }
        }
    }

    private func save(_ ratings: Set<Rating>) {
        guard case .loaded(let before) = phase, ratings != before else { return }
        phase = .saving(ratings)
        failure = nil
        let id = account.id
        Task {
            do {
                let saved = try await servers.request(id) { client throws(ChekError) in
                    try await client.setContentRatings(ratings)
                }
                phase = .loaded(Set(saved))
                servers.contentRatingsChanged(on: id)
            } catch {
                // What the library still uses stays shown, with why.
                phase = .loaded(before)
                failure = DisplayError(error)
            }
        }
    }

    /// Opens the web app in Safari, signed in with a one-time code in the
    /// fragment, which browsers never send to a server.
    private func openWeb() async {
        isOpeningWeb = true
        defer { isOpeningWeb = false }
        failure = nil
        var components = URLComponents(url: Self.webSettings, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "server", value: account.baseURL.absoluteString)]
        do {
            let id = account.id
            let code = try await servers.request(id) { client throws(ChekError) in
                try await client.webLink()
            }
            components.fragment = "code=\(code)"
        } catch .notFound {
            // A server from before web links: the web app asks to sign in.
        } catch {
            failure = DisplayError(error)
            return
        }
        if let url = components.url {
            openURL(url)
        }
    }
}
