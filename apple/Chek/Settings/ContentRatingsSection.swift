import SwiftUI

/// Which series a shared library's search and sites show, by how mature
/// their source rates them. The choice is kept by the library, so it holds
/// on every device you read it on.
struct ContentRatingsSection: View {
    let account: ServerAccount
    @Environment(ServerStore.self) private var servers
    @State private var phase = Phase.loading
    /// A change that adds mature ratings, waiting for you to confirm your age.
    @State private var pending: Set<Rating>?

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

    private var isDemo: Bool { account.id == DemoMode.accountID }

    var body: some View {
        Section {
            switch phase {
            case .loading:
                LabeledContent("Show") {
                    ProgressView()
                }
            case .failed(let error):
                LabeledContent("Show") {
                    Button("Try Again") {
                        Task { await load() }
                    }
                }
            case .loaded(let ratings), .saving(let ratings):
                Picker("Show", selection: Binding(
                    get: { custom ? Preset.custom : Preset(ratings) },
                    set: { preset in
                        if let set = preset.ratings {
                            custom = false
                            request(set)
                        } else {
                            // Custom keeps what's chosen and shows the switches.
                            custom = true
                        }
                    }
                )) {
                    ForEach(Preset.allCases, id: \.self) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                if custom || Preset(ratings) == .custom {
                    ForEach(Rating.allCases, id: \.self) { rating in
                        Toggle(String(localized: rating.title), isOn: Binding(
                            get: { ratings.contains(rating) },
                            set: { isOn in
                                var next = ratings
                                if isOn { next.insert(rating) } else { next.remove(rating) }
                                request(next)
                            }
                        ))
                        // At least one rating has to stay on.
                        .disabled(ratings == [rating])
                    }
                }
            }
        } header: {
            Text("Content")
        } footer: {
            if case .failed(let error) = phase {
                FormError(error: error)
            } else if let saveFailure {
                FormError(error: saveFailure)
            } else {
                Text(isDemo
                    ? "The sample library shows safe and suggestive series."
                    : "Applies to search and sites in this library, on all your devices.")
            }
        }
        .disabled(isDemo || isSaving)
        .task(id: account.id) {
            await load()
        }
        .confirmationDialog(
            "Show Mature Series?",
            isPresented: Binding { pending != nil } set: { if !$0 { pending = nil } },
            titleVisibility: .visible
        ) {
            Button("I'm 18 or Older") {
                UserDefaults.standard.set(true, forKey: confirmedKey)
                if let pending {
                    save(pending)
                }
            }
        } message: {
            Text("Erotica and pornographic series are for adults only.")
        }
    }

    /// Whether Custom was chosen, which keeps the switches showing even
    /// when they happen to match a preset.
    @State private var custom = false
    /// Why the last change didn't take, until the next one.
    @State private var saveFailure: DisplayError?

    private var isSaving: Bool {
        if case .saving = phase { true } else { false }
    }

    /// Where the age confirmation is kept: once per library.
    private var confirmedKey: String {
        "contentRatings.adultConfirmed.\(account.id.uuidString)"
    }

    private func load() async {
        phase = .loading
        let id = account.id
        do {
            let ratings = try await servers.request(id) { client throws(ChekError) in
                try await client.contentRatings()
            }
            phase = .loaded(Set(ratings))
        } catch {
            phase = .failed(DisplayError(error))
        }
    }

    /// Saves `ratings`, first asking your age when they add mature ones you
    /// haven't confirmed for this library.
    private func request(_ ratings: Set<Rating>) {
        guard !ratings.isEmpty else { return }
        if ratings.contains(where: \.isMature), !UserDefaults.standard.bool(forKey: confirmedKey) {
            pending = ratings
        } else {
            save(ratings)
        }
    }

    private func save(_ ratings: Set<Rating>) {
        guard case .loaded(let before) = phase, ratings != before else { return }
        phase = .saving(ratings)
        saveFailure = nil
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
                saveFailure = DisplayError(error)
            }
        }
    }
}
