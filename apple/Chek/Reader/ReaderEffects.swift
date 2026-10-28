import ChekReader
import SwiftUI

extension View {
    /// Everything the reader does in response to reading rather than to
    /// buttons: saving your place, applying settings and showing the
    /// controls on a middle tap.
    ///
    /// Each one is its own modifier so the values it watches, such as the
    /// location, redraw only it.
    func readerEffects(session: ReaderSession) -> some View {
        self
            .modifier(PositionRecorder(session: session))
            .modifier(MiddleTapHandler(controller: session.controller, session: session))
            .modifier(PreferencesApplier(session: session))
    }
}

/// Saves your place on every page turn and hides the controls once you
/// start reading.
private struct PositionRecorder: ViewModifier {
    let session: ReaderSession
    @Environment(ProgressStore.self) private var progress

    func body(content: Content) -> some View {
        content
            .onChange(of: session.controller.location) { old, location in
                guard let location, session.controller.state == .ready else { return }
                progress.record(location, in: session.item.ref, isAtEnd: session.isOnLastPage)
                // The reader refines the opening location as it lays the
                // page out, which isn't a page turn.
                if let old, !location.isSamePlace(as: old) {
                    session.hideControls()
                }
            }
            .onChange(of: session.controller.state) { _, state in
                if state == .ready {
                    progress.didOpen(session.item.ref)
                }
            }
    }
}

private struct MiddleTapHandler: ViewModifier {
    let controller: ReaderController
    let session: ReaderSession

    func body(content: Content) -> some View {
        content.onChange(of: controller.middleTapCount) {
            session.toggleControls()
        }
    }
}

/// Lays the text out again when reading settings change.
private struct PreferencesApplier: ViewModifier {
    let session: ReaderSession
    @Environment(ReaderSettings.self) private var settings

    func body(content: Content) -> some View {
        let preferences = settings.preferences(for: session.item.settingsKey)
        content.onChange(of: preferences) { _, preferences in
            let controller = session.controller
            Task { await controller.setPreferences(preferences) }
        }
    }
}

private extension Locator {
    /// Whether two locations show the same page, ignoring details the
    /// reader fills in later, such as the position number.
    func isSamePlace(as other: Locator) -> Bool {
        href == other.href
            && abs((locations.progression ?? 0) - (other.locations.progression ?? 0)) < 0.0001
    }
}
