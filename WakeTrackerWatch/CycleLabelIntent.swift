import AppIntents
import WakeTrackerCore

struct CycleLabelIntent: AppIntent {
    static var title: LocalizedStringResource = "Cycle Wake Label"
    static var description = IntentDescription("Advances waiting → riding → swimming → walking and logs a label.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            WatchSessionController.shared.cycleLabelFromActionButton()
        }
        let label = await MainActor.run { WatchSessionController.shared.currentLabel }
        return .result(dialog: "Logged \(label)")
    }
}

struct WakeTrackerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
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
