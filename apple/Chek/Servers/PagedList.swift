import Foundation
import Observation

/// A server listing loaded a page at a time as you scroll.
///
/// One request runs at a time, and a reload drops answers to requests made
/// before it, so a slow page can never land in a fresh list.
@MainActor
@Observable
final class PagedList<Item: Identifiable & Equatable & Sendable> {
    typealias Fetch = @MainActor (_ cursor: String?) async throws -> (items: [Item], next: String?)

    private(set) var items: [Item] = []
    private(set) var phase: PagedListPhase = .idle
    /// Why the last reload failed while the items from before still show.
    private(set) var staleError: DisplayError?

    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private var cursor: String?
    @ObservationIgnored private var generation = 0

    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    /// Loads the first page, unless it's already loaded.
    func loadIfNeeded() async {
        guard phase == .idle else { return }
        await reload()
    }

    /// Starts again from the first page.
    func reload() async {
        generation += 1
        let current = generation
        if items.isEmpty {
            phase = .loading
        }
        do {
            let page = try await fetch(nil)
            guard current == generation else { return }
            items = page.items
            cursor = page.next
            phase = page.next == nil ? .complete : .loaded
            staleError = nil
        } catch is CancellationError {
            guard current == generation else { return }
            phase = items.isEmpty ? .idle : .loaded
        } catch {
            guard current == generation else { return }
            if items.isEmpty {
                phase = .failed(DisplayError(error))
            } else {
                // The list stays, with a note that it may be out of date.
                phase = cursor == nil ? .complete : .loaded
                staleError = DisplayError(error)
            }
        }
    }

    /// Loads the next page when `item` is close to the end of the list.
    func loadMore(after item: Item) async {
        guard phase == .loaded, let index = items.firstIndex(where: { $0.id == item.id }), index >= items.count - 10 else { return }
        let current = generation
        phase = .loadingMore
        do {
            let page = try await fetch(cursor)
            guard current == generation else { return }
            // Pages can overlap when items are added while you scroll.
            let known = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !known.contains($0.id) })
            cursor = page.next
            phase = page.next == nil ? .complete : .loaded
        } catch {
            guard current == generation else { return }
            // Scrolling to the end again retries.
            phase = .loaded
        }
    }
}

/// Where a ``PagedList`` is in loading its pages.
enum PagedListPhase: Equatable {
    case idle
    /// The first page is loading, with nothing to show yet.
    case loading
    case loaded
    /// A later page is loading below the items already shown.
    case loadingMore
    /// Every page is loaded.
    case complete
    case failed(DisplayError)
}
