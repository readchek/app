import Foundation
import Observation

/// The app's top-level sections.
enum AppTab: String, Hashable {
    case home, library, search
}

/// Something shown in a sheet over the whole app.
enum AppSheet: String, Identifiable {
    case settings

    var id: Self { self }
}

/// Owns where you are in the app: the selected tab, any sheet and the open
/// reader. Everything that moves you around, from a tap to a file opened
/// from another app, goes through here.
@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .home
    var sheet: AppSheet?
    /// The publication open in the reader.
    var reading: ReadingItem?
    /// Whether the file picker for adding books is showing.
    var isImportingFiles = false

    func open(_ item: ReadingItem) {
        sheet = nil
        reading = item
    }

    func closeReader() {
        reading = nil
    }

    /// Shows the file picker, from wherever you asked to add books.
    func addBooks() {
        isImportingFiles = true
    }
}
