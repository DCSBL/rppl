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

/// Registers Wake Tracker under Action Button → Workout (start session only).
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

    /// Must stay `nonisolated`: Watch target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
    /// so an implicit `@MainActor perform` deadlocks against Action Button confirmation UI.
    nonisolated func perform() async throws -> some IntentResult {
        WakeLog.debug(.intent, "StartCableParkSessionIntent.perform begin")
        await WatchSessionController.shared.handleStartWorkoutIntent()
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
    }
}
