import Foundation
import RpplCore

/// `UserDefaults` persistence for `ReviewPromptState`.
enum ReviewPromptStore {
    static func load() -> ReviewPromptState {
        guard let data = UserDefaults.standard.data(forKey: AppSettingsKey.reviewPromptState),
              let state = try? JSONDecoder().decode(ReviewPromptState.self, from: data) else {
            return ReviewPromptState()
        }
        return state
    }

    static func save(_ state: ReviewPromptState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: AppSettingsKey.reviewPromptState)
    }
}
