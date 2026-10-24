import SwiftUI

/// Reading Now before there's anything to read: the first screen most
/// people see. It's the one empty screen laid out like a welcome, with its
/// action across the foot where a thumb rests, because what someone does
/// here decides whether Chek is any use to them. Your own books are the
/// one path that always works, so adding them is the one button; a shared
/// library and the sample library are offered quietly under it.
struct HomeStartView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ContentUnavailableView {
            Label("Start Reading", systemImage: "book")
        } description: {
            Text("Add books and comics from Files, or open a library someone shares with you.")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 14) {
                Button {
                    router.addBooks()
                } label: {
                    Text("Add Books")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                HStack(spacing: 24) {
                    Button("Add Shared Library") {
                        router.sheet = .addServer
                    }
                    TryDemoButton()
                }
                .buttonStyle(.borderless)
                .labelStyle(.titleOnly)
                .font(.subheadline)
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
}
