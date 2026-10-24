import SwiftUI

/// Home before there's anything to read: the first screen most people see.
/// Your own books are the one path that always works, so adding them leads
/// the sentence; a shared library and the sample library follow it.
struct HomeStartView: View {
    @Environment(AppRouter.self) private var router
    @State private var isOpeningSample = false

    var body: some View {
        EmptyState(
            "[Add books](chek-action://add) and comics from Files or iCloud Drive, or [add a library](chek-action://library) someone shares with you. You can also [open the sample library](chek-action://sample) to look around.",
            systemImage: "books.vertical",
            actions: [
                "add": { router.addBooks() },
                "library": { router.sheet = .addServer },
                "sample": { isOpeningSample = true },
            ]
        )
        .sampleLibraryOpener(isOpening: $isOpeningSample)
    }
}
