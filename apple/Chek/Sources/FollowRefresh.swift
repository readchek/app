import BackgroundTasks
import Foundation
import UserNotifications

/// Checks the series you follow for new chapters while the app is closed,
/// and tells you about them, so following means hearing about new
/// chapters rather than remembering to look.
///
/// iOS runs the check when it sees fit, usually a few times a day, and
/// only once the app has been used for a while. The app asks for it again
/// each time it goes to the background.
@MainActor
enum FollowRefresh {
    /// Listed in Info.plist under `BGTaskSchedulerPermittedIdentifiers`.
    static let taskID = "run.chibi.manga.follows.check"

    /// Called once at launch, before the app finishes launching, as iOS
    /// requires of task handlers.
    static func register(follows: FollowStore) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            // iOS calls this on its own queue; the work is the store's.
            let work = Task { @MainActor in
                let found = await follows.checkForNewChapters(force: true)
                await FollowNotifications.notify(found)
                schedule()
            }
            task.expirationHandler = { work.cancel() }
            Task {
                _ = await work.result
                task.setTaskCompleted(success: !work.isCancelled)
            }
        }
    }

    /// Asks iOS to run the check later, but no sooner than a few hours
    /// from now, since every check is a request to each source's site per
    /// series. Asking again replaces the earlier request.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = .now.addingTimeInterval(4 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// The notifications about new chapters, and the permission to show them.
@MainActor
enum FollowNotifications {
    /// Asks to show notifications the first time you follow a series,
    /// which is when they first mean something. Asking before would be
    /// asking for nothing in particular, and iOS lets an app ask once.
    static func askIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    /// One notification per series with new chapters, replacing the last
    /// about that series so they don't pile up.
    static func notify(_ found: [FollowStore.NewChapters]) async {
        guard !found.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        for item in found {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.count == 1
                ? String(localized: "A new chapter is out.")
                : String(localized: "\(item.count) new chapters are out.")
            content.sound = .default
            content.threadIdentifier = item.key
            content.userInfo = [
                "server": item.server.uuidString,
                "source": item.source,
                "series": item.seriesID,
                "title": item.title,
            ]
            try? await center.add(UNNotificationRequest(identifier: item.key, content: content, trigger: nil))
        }
    }

    /// Where a tapped notification leads: the series it was about.
    static func route(for notification: UNNotification) -> Route? {
        let info = notification.request.content.userInfo
        guard let server = (info["server"] as? String).flatMap(UUID.init),
              let source = info["source"] as? String,
              let series = info["series"] as? String,
              let title = info["title"] as? String
        else { return nil }
        return .sourceSeries(server, source: source, seriesID: series, title: title)
    }
}

/// Opens the series a tapped notification was about.
final class NotificationOpener: NSObject, UNUserNotificationCenterDelegate {
    private let router: AppRouter

    init(router: AppRouter) {
        self.router = router
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let route = FollowNotifications.route(for: response.notification) else { return }
        router.show(route)
    }

    /// While you're in the app the Following shelf shows what's new, so
    /// a notification arriving then stays quiet.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        []
    }
}
