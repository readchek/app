import SwiftUI

/// On the last page of a book or comic that isn't part of a series, a
/// way out, so finishing doesn't leave you on a page with nothing on.
struct BookEndButton: View {
    let session: ReaderSession
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack {
            Spacer()
            if isOnLastPage {
                Button {
                    router.closeReader()
                } label: {
                    Label("Finished", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: isOnLastPage)
    }

    private var isOnLastPage: Bool {
        guard let count = session.controller.positions?.count, count > 1,
              let position = session.controller.location?.locations.position
        else { return false }
        return position >= count
    }
}
