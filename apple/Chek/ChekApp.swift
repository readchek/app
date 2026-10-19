import ChekReader
import SwiftData
import SwiftUI

@main
struct ChekApp: App {
    let modelContainer: ModelContainer

    init() {
        ReaderFormats.registerDefaults()
        // Chek ships as an update to Chibi Manga under the same bundle id, and
        // Chibi Manga keeps its SwiftData models in the default store. A
        // store of Chek's own keeps the two schemas from meeting, and leaves
        // Chibi Manga's data in place for importing later.
        do {
            modelContainer = try ModelContainer(
                for: Book.self,
                configurations: ModelConfiguration("Chek")
            )
        } catch {
            fatalError("Couldn't open the library: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
        .modelContainer(modelContainer)
    }
}
