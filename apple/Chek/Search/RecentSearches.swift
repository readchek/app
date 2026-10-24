import Foundation
import Observation
import SwiftUI

/// What you searched for lately, newest first, kept on this device so a
/// search you make often is a tap away.
@MainActor
@Observable
final class RecentSearches {
    private static let key = "search.recent"
    private static let limit = 10

    private(set) var items: [String]

    init() {
        items = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    func add(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        items.removeAll { $0.localizedCaseInsensitiveCompare(query) == .orderedSame }
        items.insert(query, at: 0)
        items = Array(items.prefix(Self.limit))
        save()
    }

    func remove(_ query: String) {
        items.removeAll { $0 == query }
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func save() {
        UserDefaults.standard.set(items, forKey: Self.key)
    }
}

/// Search before you've typed: your recent searches, or what Search looks
/// through when there are none yet.
struct RecentSearchesView: View {
    let recents: RecentSearches
    let search: (String) -> Void

    var body: some View {
        if recents.items.isEmpty {
            // No title: the page is already called Search, and the symbol
            // says the rest. Laid out as an empty state is, since one
            // without a title shrinks its symbol.
            VStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Find books, comics, and authors in your library, shared libraries, and sites.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    ForEach(recents.items, id: \.self) { query in
                        Button {
                            search(query)
                        } label: {
                            Label(query, systemImage: "clock.arrow.circlepath")
                                .foregroundStyle(.primary)
                        }
                        .swipeActions {
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                recents.remove(query)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Recent")
                        Spacer()
                        Button("Clear") {
                            withAnimation { recents.clear() }
                        }
                        .font(.subheadline)
                        .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}
