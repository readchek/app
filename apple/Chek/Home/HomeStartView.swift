import SwiftUI

/// Reading Now before there's anything to read: the first screen most
/// people see. Your own books are the one path that always works, so
/// adding them is the one button; a shared library and the sample books
/// are offered quietly under it.
struct HomeStartView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                Text("Nothing to Read Yet")
                    .font(.title2.bold())
                Text("Add books and comics you have in Files or iCloud Drive. They stay on this device.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Spacer()
            VStack(spacing: 16) {
                Button {
                    router.addBooks()
                } label: {
                    Text("Add Books")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text("Someone shared a library with you?")
                            .foregroundStyle(.secondary)
                        Button("Add It") {
                            router.sheet = .addServer
                        }
                    }
                    TryDemoButton()
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
                .labelStyle(.titleOnly)
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}
