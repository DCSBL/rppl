import Foundation
import UserNotifications
import WatchKit
import RpplCore

/// Local notifications for Watch→phone sync outcomes.
enum WatchSyncNotifier {
    private static let categoryId = "rppl.sync"

    /// Request alert permission in context (first transfer), not at cold launch.
    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                WakeLog.debug(.sync, "notification auth granted=\(granted)")
            } catch {
                WakeLog.error(.sync, "notification auth: \(error.localizedDescription)")
            }
        case .denied:
            WakeLog.debug(.sync, "notification auth denied — skip prompts")
        default:
            break
        }
    }

    /// Fire when phone ack confirms the session is safe on iPhone.
    static func notifySyncCompleted(sessionId: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            else {
                WakeLog.debug(.sync, "skip sync notify — not authorized")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = String(localized: "Session synced")
            content.body = String(localized: "Park day is on your iPhone.")
            content.sound = .default
            content.categoryIdentifier = categoryId
            content.userInfo = [AppConstants.wcAckMessageKey: sessionId]

            let request = UNNotificationRequest(
                identifier: "rppl.sync.\(sessionId)",
                content: content,
                trigger: nil
            )
            do {
                try await center.add(request)
                WakeLog.debug(.sync, "scheduled sync notify \(sessionId.prefix(8))…")
            } catch {
                WakeLog.error(.sync, "sync notify: \(error.localizedDescription)")
            }
        }
    }
}
