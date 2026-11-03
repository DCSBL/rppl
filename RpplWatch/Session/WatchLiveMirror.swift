import Foundation
import HealthKit
import RpplCore

/// A viewing window for the iPhone: mirrors the running workout to the companion and sends a
/// `WatchLiveSnapshot` every few seconds when something on screen changed. Best effort and read-only:
/// it never touches recording, detection, the Health save or the transfer, and every failure is only logged.
@MainActor
final class WatchLiveMirror {
    static let shared = WatchLiveMirror()

    private static let interval: Duration = .seconds(3)
    private var task: Task<Void, Never>?

    func begin(_ session: HKWorkoutSession, controller: WatchSessionController) {
        task?.cancel()
        task = Task { [weak controller] in
            do {
                try await session.startMirroringToCompanionDevice()
            } catch {
                WakeLog.debug(.workout, "live mirror unavailable: \(error.localizedDescription)")
                return
            }
            var last: WatchLiveSnapshot?
            while !Task.isCancelled, session.state == .running || session.state == .paused {
                if let controller, let startedAt = controller.startedAt {
                    let snapshot = Self.snapshot(of: controller, startedAt: startedAt)
                    if last.map({ !snapshot.showsSame(as: $0) }) ?? true,
                       let data = try? snapshot.encoded() {
                        do {
                            try await session.sendToRemoteWorkoutSession(data: data)
                            last = snapshot
                        } catch {
                            WakeLog.debug(.workout, "live mirror send: \(error.localizedDescription)")
                        }
                    }
                }
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    private static func snapshot(of controller: WatchSessionController, startedAt: Date) -> WatchLiveSnapshot {
        let now = Date()
        return WatchLiveSnapshot(
            startedAt: startedAt,
            sentAt: now,
            setCount: controller.setCount,
            setStartedAt: controller.isSetOngoing ? now.addingTimeInterval(-controller.currentSetDuration) : nil,
            speedKmh: controller.isSetOngoing ? controller.currentSetSpeedKmh : nil,
            heartRate: controller.lastHeartRate,
            waterCelsius: controller.waterTemperatureDisplay?.celsius,
            lapCount: controller.isSetOngoing ? controller.currentSetLapCount : controller.lastSetLapCount,
            isPaused: controller.isProductPaused
        )
    }
}
