import Observation
import RpplCore
import SwiftUI
import UIKit
import UserNotifications

/// The one session tracked live on this iPhone (no Watch). State is written to disk on every change, so a
/// force quit loses nothing; stopping turns it into a manual session. Never touches HealthKit.
@Observable
@MainActor
final class LiveSessionController {
    static let shared = LiveSessionController()

    private(set) var session: LiveSession?
    /// The running-session screen is up.
    var showsScreen = false
    /// "Is your session still running?": after a relaunch, or two hours without a tap.
    var asksToContinue = false
    var errorText: String?
    /// The Live Activity's Stop button: the running screen opens on its stop question.
    var stopRequested = false

    private let file: LiveSessionFile
    private static let reminderID = "nl.dcsbl.rppl.live-session-reminder"

    private init() {
        let base = URL.applicationSupportDirectory.appending(path: "LiveSession", directoryHint: .isDirectory)
        file = LiveSessionFile(url: base.appending(path: "live-session.json"))
        session = file.load()
        asksToContinue = session != nil
        NextSetIntent.handler = { LiveSessionController.shared.nextSet() }
    }

    var park: Park? {
        guard let id = session?.parkId else { return nil }
        return ParkCatalog.loadApp().first { $0.id == id }
    }

    /// The park, or "City, Country" of the own spot; nil when neither is known.
    var placeName: String? { park?.compactName ?? session?.spotName }

    func start(parkId: String?, spot: ParkCoordinate?, spotName: String?) {
        guard session == nil else { return }
        let live = LiveSession(startedAt: .now, parkId: parkId, spot: spot, spotName: spotName)
        persist(live)
        requestReminderAccess()
        if let spot, spotName == nil { Task { await resolveSpotName(spot, sessionId: live.id) } }
    }

    /// Starting never waits for the geocoder: the name lands on the running session when it answers.
    private func resolveSpotName(_ spot: ParkCoordinate, sessionId: String) async {
        guard let name = await SessionCityResolver.shared.placeName(near: spot),
              var live = session, live.id == sessionId, live.spotName == nil
        else { return }
        live.spotName = name
        persist(live)
    }

    func nextSet() {
        guard var live = session, live.nextSet(at: .now) else { return }
        persist(live)
    }

    /// "Keep going" after the still-running question.
    func keepGoing() {
        guard var live = session else { return }
        live.touch(at: .now)
        asksToContinue = false
        persist(live)
    }

    /// Called when the app becomes active: a long silence asks the question.
    func checkStillRunning(now: Date = .now) {
        if let live = session, now >= live.stillRunningCheckAt { asksToContinue = true }
    }

    func discard() {
        clear()
    }

    /// Saves the session as a manual session ending at `end` (now, or the last activity of an orphan).
    /// Returns its id, or nil when saving failed (the session stays, `errorText` says why).
    @discardableResult
    func finish(at end: Date = .now) async -> String? {
        guard let live = session else { return nil }
        let store = PhoneConnectivityService.shared.store
        let park = self.park
        let end = max(end, live.startedAt)
        let entry = live.entry(location: park?.location)
        let label = park?.compactName ?? (live.spot == nil ? nil : (live.spotName ?? String(localized: "Own location")))
        let parkId = park?.id
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let system = UIDevice.current.systemVersion
        do {
            try await StoreIO.runOffMain {
                let manifest = SessionManifest(
                    sessionId: live.id,
                    testerId: TesterIdentity.resolve(),
                    appVersion: version,
                    buildNumber: build,
                    watchModel: "none",
                    systemVersion: system,
                    startedAt: live.startedAt,
                    endedAt: end,
                    transferState: .acknowledged,
                    activityCode: ActivityCodes.wakeboard,
                    parkId: parkId,
                    parkIdSource: SessionParkSource.manual,
                    manual: entry
                )
                try store.saveManual(manifest, label: label)
            }
        } catch {
            errorText = error.localizedDescription
            WakeLog.error(.store, "live session save: \(error.localizedDescription)")
            return nil
        }
        PhoneICloudDriveController.shared.acceptSession(live.id)
        PhoneConnectivityService.shared.bumpSessionsRevision()
        clear()
        if let spot = entry.location {
            Task {
                await ManualSessionWeather.refresh(store: store, sessionId: live.id, at: spot, from: live.startedAt, to: end)
            }
        }
        return live.id
    }

    /// The end of an orphaned session: its last activity.
    func finishAtLastActivity() async -> String? {
        asksToContinue = false
        return await finish(at: session?.lastActivityAt ?? .now)
    }

    private func persist(_ live: LiveSession) {
        session = live
        do { try file.save(live) } catch {
            WakeLog.error(.store, "live session write: \(error.localizedDescription)")
        }
        scheduleReminder(at: live.stillRunningCheckAt)
        LiveSessionActivityManager.sync(live, parkName: park?.compactName ?? live.spotName)
    }

    private func clear() {
        session = nil
        showsScreen = false
        asksToContinue = false
        file.remove()
        LiveSessionActivityManager.end()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.reminderID])
    }

    // MARK: Reminder

    /// Just in time: the first session start, not launch. A "no" only means no reminder.
    private func requestReminderAccess() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func scheduleReminder(at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Is your session still running?")
        content.body = String(localized: "Open Rppl to keep going or end it.")
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.reminderID, content: content, trigger: trigger))
    }
}
