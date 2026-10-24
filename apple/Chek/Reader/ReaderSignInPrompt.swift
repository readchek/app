import SwiftUI

extension View {
    /// Offers to sign in again when the server a publication is read from
    /// ends its session mid-read, and picks reading back up once you have.
    func readerSignIn(session: ReaderSession) -> some View {
        modifier(ReaderSignInPrompt(session: session))
    }
}

private struct ReaderSignInPrompt: ViewModifier {
    let session: ReaderSession
    @Environment(ServerStore.self) private var servers

    func body(content: Content) -> some View {
        @Bindable var session = session
        let account = session.item.ref.server
        // A publication that's all on the device needs no session to read.
        let isSignedOut = !session.item.isOnDevice && (account.map { servers.state(of: $0) == .signedOut } ?? false)
        content
            .overlay(alignment: .bottom) {
                // Pages that failed show their own notice; this says what
                // to do about it, once, above the bottom bar.
                if isSignedOut, session.phase == .reading, session.controller.state == .ready {
                    SignedOutBanner(name: account.flatMap(servers.account)?.name ?? "", session: session)
                        .padding(.bottom, ReaderScreen.bottomBarHeight + 56)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: isSignedOut)
            .sheet(isPresented: $session.isSigningIn) {
                if let account {
                    SignInView(account: account)
                }
            }
            .onChange(of: isSignedOut) { was, now in
                // Signed in again, from here or elsewhere: the pages that
                // failed load afresh from where you are.
                if was, !now {
                    Task { await session.reopen() }
                }
            }
    }
}

private struct SignedOutBanner: View {
    let name: String
    let session: ReaderSession

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Signed Out of \(name)")
                    .font(.subheadline.weight(.semibold))
                Text("Sign in to keep reading.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Sign In") {
                session.isSigningIn = true
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: 420)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .padding(.horizontal, 16)
    }
}
