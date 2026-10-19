import ChekReader
import SwiftUI

extension View {
    /// Asks whether to go to where you are on another device, when the
    /// server has a place there that differs from the one here.
    func otherDevicePrompt(session: ReaderSession) -> some View {
        modifier(OtherDevicePrompt(session: session))
    }
}

private struct OtherDevicePrompt: ViewModifier {
    let session: ReaderSession
    @Environment(ServerSync.self) private var sync

    func body(content: Content) -> some View {
        let prompt = session.controller.state == .ready ? sync.prompts[session.item.ref] : nil
        content.alert(
            title(for: prompt),
            isPresented: Binding { prompt != nil } set: { if !$0 { sync.keepThisDevicePosition(for: session.item.ref) } }
        ) {
            Button("Go There") {
                if let locator = sync.useOtherDevicePosition(for: session.item.ref) {
                    Task { await session.controller.go(to: locator) }
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Stay Here", role: .cancel) {
                sync.keepThisDevicePosition(for: session.item.ref)
            }
        } message: {
            if let updatedAt = prompt?.updatedAt {
                Text("Saved \(updatedAt, format: .relative(presentation: .named)).")
            }
        }
    }

    private func title(for prompt: OtherDevicePosition?) -> String {
        guard let prompt else { return "" }
        let place = prompt.locator.locations.totalProgression.map { $0.formatted(.percent.precision(.fractionLength(0))) }
        switch (prompt.device, place) {
        case let (device?, place?): return String(localized: "You're at \(place) on \(device)")
        case let (nil, place?): return String(localized: "You're at \(place) on another device")
        case let (device?, nil): return String(localized: "You're somewhere else on \(device)")
        case (nil, nil): return String(localized: "You're somewhere else on another device")
        }
    }
}
