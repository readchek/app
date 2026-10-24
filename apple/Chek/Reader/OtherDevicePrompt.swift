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
            Button("Continue") {
                if let locator = sync.useOtherDevicePosition(for: session.item.ref) {
                    Task { await session.controller.go(to: locator) }
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Not Now", role: .cancel) {
                sync.keepThisDevicePosition(for: session.item.ref)
            }
        } message: {
            if let prompt {
                Text(message(for: prompt))
            }
        }
    }

    private func title(for prompt: OtherDevicePosition?) -> String {
        guard let prompt else { return "" }
        if let device = prompt.device {
            return String(localized: "Continue From \(device)?")
        }
        return String(localized: "Continue From Another Device?")
    }

    /// Where the other device is and when it got there, as far as known.
    private func message(for prompt: OtherDevicePosition) -> String {
        let device = prompt.device ?? String(localized: "Another device")
        let place = prompt.locator.locations.totalProgression.map { $0.formatted(.percent.precision(.fractionLength(0))) }
        let saved = prompt.updatedAt.map { $0.formatted(.relative(presentation: .named)) }
        switch (place, saved) {
        case let (place?, saved?): return String(localized: "\(device) was at \(place), saved \(saved).")
        case let (place?, nil): return String(localized: "\(device) was at \(place).")
        case let (nil, saved?): return String(localized: "\(device) is further along, saved \(saved).")
        case (nil, nil): return String(localized: "\(device) is further along.")
        }
    }
}
