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

    @MainActor
    func perform() async throws -> some IntentResult {
        if !WatchSessionController.shared.isRunning {
            await WatchSessionController.shared.startSession()
        }
        // First Action Button press starts the session; subsequent presses run Cycle Label.
        return .result(actionButtonIntent: CycleLabelIntent())
    }
}

/// Next Action Button press while a workout session is active.
struct CycleLabelIntent: AppIntent {
    static var title: LocalizedStringResource = "Cycle Label"
    static var description = IntentDescription(
        "Advances waiting → riding → swimming → walking and logs a label."
    )
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        WatchSessionController.shared.cycleLabelFromActionButton()
        let label = WatchSessionController.shared.currentLabel
        // Keep Action Button armed for the next cycle press.
        try? await StartCableParkSessionIntent().donate(
            result: .result(actionButtonIntent: CycleLabelIntent())
        )
        return .result(dialog: IntentDialog(stringLiteral: "Logged \(label)"))
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
