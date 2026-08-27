import Foundation

/// Cross-tab logbook navigation (Settings import → session detail, highlight on return).
struct LogbookNavigationRequest: Equatable {
    var openSessionId: String?
    var highlightSessionId: String?
}
