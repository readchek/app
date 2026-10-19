import ChekReader
import SwiftData
import SwiftUI

@main
struct ChekApp: App {
    init() {
        ReaderFormats.registerDefaults()
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
        .modelContainer(for: Book.self)
    }
}
