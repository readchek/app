import Foundation
import SwiftUI

/// A newer Chek on the App Store than the one running.
nonisolated struct AppUpdate: Equatable, Sendable {
    let version: String
    /// Its page on the App Store, which is where it's updated from.
    let store: URL
}

/// Asks the App Store what version of Chek it has. iOS updates apps by
/// itself in time but has no way for an app to ask whether one is
/// waiting, so this reads the store's public listing for the app.
nonisolated enum AppUpdateCheck {
    private static let lastAskedKey = "appUpdate.lastAsked"
    private static let offeredKey = "appUpdate.offered"
    /// The store is asked once a day at most.
    private static let interval: TimeInterval = 24 * 60 * 60

    /// The update to offer now, if there is one that hasn't been offered
    /// before. Nil when up to date, offline, or asked recently.
    static func look(defaults: UserDefaults = .standard, now: Date = .now) async -> AppUpdate? {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        else { return nil }
        if let last = defaults.object(forKey: lastAskedKey) as? Date, now.timeIntervalSince(last) < interval {
            return nil
        }
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [URLQueryItem(name: "bundleId", value: bundleID)]
        // Each country's store has its own listing, and a version reaches
        // them at different times.
        if let region = Locale.current.region?.identifier {
            components?.queryItems?.append(URLQueryItem(name: "country", value: region.lowercased()))
        }
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        defaults.set(now, forKey: lastAskedKey)
        guard let update = update(in: data, installed: installed),
              defaults.string(forKey: offeredKey) != update.version
        else { return nil }
        return update
    }

    /// Notes that `update` was offered, so the same version isn't offered
    /// again whatever the answer was.
    static func didOffer(_ update: AppUpdate, defaults: UserDefaults = .standard) {
        defaults.set(update.version, forKey: offeredKey)
    }

    /// The update the store's answer describes, when it's newer than
    /// `installed`.
    static func update(in data: Data, installed: String) -> AppUpdate? {
        struct Answer: Decodable {
            struct Listing: Decodable {
                let version: String
                let trackViewUrl: String
            }

            let results: [Listing]
        }
        guard let listing = (try? JSONDecoder().decode(Answer.self, from: data))?.results.first,
              isNewer(listing.version, than: installed),
              let store = URL(string: listing.trackViewUrl), store.scheme == "https"
        else { return nil }
        return AppUpdate(version: listing.version, store: store)
    }

    /// Whether version `candidate` comes after `installed`, comparing
    /// their numbers part by part, so 2.10 is newer than 2.9.
    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        let parts = { (version: String) in version.split(separator: ".").map { Int($0) ?? 0 } }
        let (new, old) = (parts(candidate), parts(installed))
        for index in 0..<max(new.count, old.count) {
            let (a, b) = (index < new.count ? new[index] : 0, index < old.count ? old[index] : 0)
            if a != b {
                return a > b
            }
        }
        return false
    }
}

extension View {
    /// Says once when a newer Chek is on the App Store, with the system's
    /// own alert and a way there.
    func appUpdateNotice() -> some View {
        modifier(AppUpdateNotice())
    }
}

private struct AppUpdateNotice: ViewModifier {
    @State private var update: AppUpdate?
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .task {
                update = await AppUpdateCheck.look()
            }
            .alert("Update Available", isPresented: Binding(get: { update != nil }, set: { if !$0 { update = nil } }), presenting: update) { update in
                Button("Update") {
                    AppUpdateCheck.didOffer(update)
                    openURL(update.store)
                }
                Button("Not Now", role: .cancel) {
                    AppUpdateCheck.didOffer(update)
                }
            } message: { update in
                Text("Chek \(update.version) is on the App Store.")
            }
    }
}
