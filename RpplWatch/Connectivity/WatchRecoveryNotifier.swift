import Foundation
import UserNotifications
import WatchKit
import RpplCore

/// Tells the rider that recording stopped after a crash. watchOS relaunches the app without any
/// UI, so without this the rider keeps riding with nothing being recorded.
@MainActor
enum WatchRecoveryNotifier {
    /// A failure haptic, plus a banner when notifications are already allowed (the prompt is shown
    /// in context after the first sync, never at launch).
    static func notifyRecordingStopped(at endedAt: Date) async {
        WKInterfaceDevice.current().play(.failure)

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        else {
            WakeLog.debug(.session, "skip recovery notify — not authorized")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Recording stopped")
        content.body = String(
            format: String(localized: "Rppl stopped after a problem. Everything up to %@ is saved. Start a new session."),
            endedAt.formatted(date: .omitted, time: .shortened)
        )
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "rppl.recovery.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
            WakeLog.debug(.session, "scheduled recovery notify")
        } catch {
            WakeLog.error(.session, "recovery notify: \(error.localizedDescription)")
        }
    }
}
