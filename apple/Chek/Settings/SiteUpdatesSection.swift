import SwiftUI

/// Whether a shared library's sites update by themselves, and the updates
/// waiting when they don't.
struct SiteUpdatesSection: View {
    let account: ServerAccount
    @Environment(SiteUpdates.self) private var siteUpdates

    var body: some View {
        let pending = siteUpdates.pending[account.id] ?? 0
        let isChecking = siteUpdates.checking.contains(account.id)
        Section {
            Toggle("Update Sites Automatically", isOn: Binding(
                get: { siteUpdates.isAutomatic(account.id) },
                set: { siteUpdates.setAutomatic($0, for: account.id) }
            ))
            if isChecking {
                Label {
                    Text("Checking for updates…")
                        .foregroundStyle(.secondary)
                } icon: {
                    ProgressView()
                }
            } else if pending > 0 {
                Button("Update ^[\(pending) Site](inflect: true)") {
                    Task { await siteUpdates.updateAll(account.id) }
                }
            }
        } header: {
            Text("Sites")
        } footer: {
            Text(siteUpdates.isAutomatic(account.id)
                ? "Chek looks for new versions of this library's sites a few times a day and installs them."
                : "Chek looks for new versions of this library's sites a few times a day and shows how many are waiting on the Shared tab.")
        }
        .task(id: account.id) {
            await siteUpdates.check(account.id, force: false)
        }
    }
}
