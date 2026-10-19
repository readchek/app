import SwiftUI

extension View {
    /// Shows files that couldn't be added to the library, wherever the
    /// import started.
    func importFailureAlert() -> some View {
        modifier(ImportFailureAlert())
    }
}

/// Split out so the root view doesn't redraw when an import fails.
private struct ImportFailureAlert: ViewModifier {
    @Environment(LibraryStore.self) private var library

    func body(content: Content) -> some View {
        @Bindable var library = library
        content
            .alert(
                library.failures.count == 1 ? "Couldn't Add This File" : "Couldn't Add Some Files",
                isPresented: $library.isShowingFailures
            ) {
                Button("OK") {}
            } message: {
                Text(library.failureSummary)
            }
    }
}
