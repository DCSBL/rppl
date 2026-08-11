import AppIntents
import WakeTrackerCore

/// Workout style shown under Settings › Action Button › Workout › App.
enum CableParkWorkoutStyle: String, AppEnum {
    case cablePark

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Workout")

    static var caseDisplayRepresentations: [CableParkWorkoutStyle: DisplayRepresentation] = [
        .cablePark: DisplayRepresentation(
            title: "Cable Park",
            subtitle: "Wake Tracker session"
        )
    ]
}

/// Registers Wake Tracker under Action Button → Workout.
struct StartCableParkSessionIntent: StartWorkoutIntent {
    static var title: LocalizedStringResource = "Start Cable Park Session"
    static var description = IntentDescription("Starts a Wake Tracker cable-park recording session.")
    static var openAppWhenRun: Bool { true }

    static var suggestedWorkouts: [StartCableParkSessionIntent] = [
        StartCableParkSessionIntent()
    ]

    @Parameter(title: "Type of Workout")
    var workoutStyle: CableParkWorkoutStyle

    init() {
        workoutStyle = .cablePark
    }

    init(workoutStyle: CableParkWorkoutStyle) {
        self.workoutStyle = workoutStyle
    }

    var displayRepresentation: DisplayRepresentation {
        CableParkWorkoutStyle.caseDisplayRepresentations[workoutStyle]
            ?? DisplayRepresentation(title: "Cable Park")
    }

    func perform() async throws -> some IntentResult {
        WakeLog.debug(.intent, "StartCableParkSessionIntent.perform begin")
        let running = await WatchSessionController.shared.isRunning
        if running {
            // Backup: some OS builds re-fire Start instead of donated next action.
            WakeLog.debug(.intent, "StartCableParkSessionIntent: already running — cycle label")
            await WatchSessionController.shared.cycleLabelFromActionButton()
        } else {
            WakeLog.debug(.intent, "StartCableParkSessionIntent: starting session")
            await WatchSessionController.shared.startSession()
        }
        return .result(actionButtonIntent: CycleLabelIntent())
    }
}

/// Donated Action Button next-action while a workout session is active.
///
/// Critical: `openAppWhenRun` must stay **false**. Opening the app from the Action Button
/// during an active workout / Water Lock often yields a blank red flash and never calls
/// `perform()` (no logs, label unchanged).
struct CycleLabelIntent: AppIntent {
    static var title: LocalizedStringResource = "Cycle Label"
    static var description = IntentDescription(
        "Advances waiting → riding → swimming → walking and logs a label."
    )
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        WakeLog.debug(.intent, "CycleLabelIntent.perform begin")
        await WatchSessionController.shared.cycleLabelFromActionButton()
        WakeLog.debug(.intent, "CycleLabelIntent.perform done")
        return .result()
    }
}

struct WakeTrackerShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .blue }

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartCableParkSessionIntent(),
            phrases: [
                "Start cable park in \(.applicationName)",
                "Start session in \(.applicationName)"
            ],
            shortTitle: "Start Session",
            systemImageName: "figure.surfing"
        )
        AppShortcut(
            intent: CycleLabelIntent(),
            phrases: [
                "Cycle wake label in \(.applicationName)",
                "Log wake label with \(.applicationName)"
            ],
            shortTitle: "Cycle Label",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}
