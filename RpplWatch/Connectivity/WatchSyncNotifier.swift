import Foundation
import UserNotifications
import WatchKit
import RpplCore

/// Local notifications for Watch→phone sync outcomes.
@MainActor
enum WatchSyncNotifier {
    private static let categoryId = "rppl.sync"
    private static let coalesceNanoseconds: UInt64 = 750_000_000

    private static var pendingSessionIds: Set<String> = []
    private static var coalesceTask: Task<Void, Never>?

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

    /// Queue a sync-complete alert for a session that newly reached phone ack.
    /// Rapid acks coalesce into one banner (singular or plural).
    static func notifySyncCompleted(sessionId: String) {
        pendingSessionIds.insert(sessionId)
        coalesceTask?.cancel()
        coalesceTask = Task {
            try? await Task.sleep(nanoseconds: coalesceNanoseconds)
            guard !Task.isCancelled else { return }
            let ids = pendingSessionIds
            pendingSessionIds.removeAll()
            guard !ids.isEmpty else { return }
            await presentSyncCompleted(sessionCount: ids.count)
        }
    }

    private static func presentSyncCompleted(sessionCount: Int) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        else {
            WakeLog.debug(.sync, "skip sync notify — not authorized")
            return
        }

        let content = UNMutableNotificationContent()
        if sessionCount <= 1 {
            content.title = String(localized: "Session synced")
            content.body = String(localized: "Park day is on your iPhone.")
        } else {
            content.title = String(localized: "Sessions synced")
            content.body = String(format: String(localized: "%lld park days are on your iPhone."), sessionCount)
        }
        content.sound = .default
        content.categoryIdentifier = categoryId

        let request = UNNotificationRequest(
            identifier: "rppl.sync.batch.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
            WakeLog.debug(.sync, "scheduled sync notify count=\(sessionCount)")
        } catch {
            WakeLog.error(.sync, "sync notify: \(error.localizedDescription)")
        }
    }
}
