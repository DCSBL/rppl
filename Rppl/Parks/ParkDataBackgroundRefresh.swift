import BackgroundTasks
import RpplCore
import WidgetKit

/// Daily park data refresh in the background, only while a park widget is on a Home or Lock Screen
/// (the widgets are what benefit from fresher data). Without one, the in-app check is enough.
enum ParkDataBackgroundRefresh {
    static let taskIdentifier = "nl.dcsbl.rppl.parkDataRefresh"
    private static let relevantWidgetKinds: Set<String> = ["nl.dcsbl.rppl.parkHours", "nl.dcsbl.rppl.topParks"]

    private struct TaskBox: @unchecked Sendable {
        let task: BGAppRefreshTask
    }

    /// Call once while the app launches. The handler runs on the main queue.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: .main) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(TaskBox(task: task))
        }
    }

    private static func handle(_ box: TaskBox) {
        let work = Task { @MainActor in
            await updateSchedule()
            let controller = ParkDataUpdateController.shared
            let success = await controller.backgroundRefresh()
            WakeLog.debug(.store, "park data background refresh success=\(success)")
            box.task.setTaskCompleted(success: success)
        }
        box.task.expirationHandler = { work.cancel() }
    }

    /// Plans the next check at this installation's fixed time of day, or cancels it when updates are
    /// off or no park widget is installed. Call when the app goes to the background and from the task.
    @MainActor
    static func updateSchedule() async {
        let scheduler = BGTaskScheduler.shared
        guard ParkDataUpdateController.shared.isEnabled, await hasRelevantWidget() else {
            scheduler.cancel(taskRequestWithIdentifier: taskIdentifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = ParkDataRefreshPolicy.nextDailyCheck(
            after: Date(),
            offsetFraction: ParkDataUpdateController.shared.dailyOffsetFraction()
        )
        do {
            try scheduler.submit(request)
        } catch {
            WakeLog.error(.store, "park data background schedule: \(error.localizedDescription)")
        }
    }

    private static func hasRelevantWidget() async -> Bool {
        let kinds = relevantWidgetKinds
        return await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                switch result {
                case .success(let infos): continuation.resume(returning: infos.contains { kinds.contains($0.kind) })
                case .failure: continuation.resume(returning: false)
                }
            }
        }
    }
}
