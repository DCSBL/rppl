import ActivityKit
import Foundation
import RpplCore

/// Keeps the Live Activity in step with the running `LiveSession`. Best effort: a refusal (activities
/// off, or a start from the background) never affects the session itself.
@MainActor
enum LiveSessionActivityManager {
    private typealias Activities = Activity<LiveSessionActivityAttributes>

    static func sync(_ live: LiveSession, parkName: String?) {
        let content = ActivityContent(
            state: LiveSessionActivityAttributes.ContentState(live),
            // Grey out when nothing touched the session for the still-running window.
            staleDate: live.stillRunningCheckAt
        )
        if let running = Activities.activities.first(where: { $0.attributes.startedAt == live.startedAt }) {
            Task { await running.update(content) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            _ = try Activities.request(
                attributes: LiveSessionActivityAttributes(startedAt: live.startedAt, parkName: parkName),
                content: content
            )
        } catch {
            WakeLog.debug(.ui, "live activity request: \(error.localizedDescription)")
        }
    }

    static func end() {
        for activity in Activities.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
