import Observation
import RpplCore
import SwiftUI

/// The pages of the park editor. A new park walks through them in order; an existing park opens a
/// list of them.
enum ParkEditorPage: Int, CaseIterable, Hashable {
    case basics, contact, about, cables, opening, prices

    var title: LocalizedStringKey {
        switch self {
        case .basics: "Basics"
        case .contact: "Contact and links"
        case .about: "About"
        case .cables: "Cables"
        case .opening: "Opening times"
        case .prices: "Prices"
        }
    }

    var systemImage: String {
        switch self {
        case .basics: "mappin.and.ellipse"
        case .contact: "phone"
        case .about: "text.alignleft"
        case .cables: "scribble.variable"
        case .opening: "clock"
        case .prices: "eurosign.circle"
        }
    }

    /// The sections (as the diff and the issues know them) this page edits.
    var sections: [ParkSection] {
        switch self {
        case .basics: [.basics, .location]
        case .contact: [.contact, .links]
        case .about: [.about]
        case .cables: [.cables]
        case .opening: [.opening]
        case .prices: [.prices]
        }
    }

    static func page(for section: ParkSection) -> ParkEditorPage {
        switch section {
        case .basics, .location: .basics
        case .contact, .links: .contact
        case .about: .about
        case .cables: .cables
        case .opening: .opening
        case .prices: .prices
        }
    }
}

/// Where the guided flow is: a welcome, the pages, a review.
enum ParkEditorStep: Hashable {
    case welcome
    case page(ParkEditorPage)
    case review

    static let guided: [ParkEditorStep] = [.welcome] + ParkEditorPage.allCases.map { .page($0) } + [.review]
}

/// Detail screens pushed on top of a page. The number is the index in the list it belongs to.
enum ParkEditorRoute: Hashable {
    case page(ParkEditorPage)
    case cable(Int)
    case rule(Int)
    case block(Int)
    case price(Int)
}

/// A destructive step that waits for a yes: deleting a cable, an opening hours row, a price.
struct ParkEditorDeletion {
    let title: String
    let message: String
    let perform: () -> Void
}

@Observable
@MainActor
final class ParkEditorSession {
    var park: Park
    let initial: Park
    let draftID: String
    /// `id` of the park being edited; nil for a new park.
    let editsParkID: String?
    /// Position in `ParkEditorStep.guided`, only used when `isGuided`.
    var step: Int
    var path: [ParkEditorRoute] = []
    var deletion: ParkEditorDeletion?
    /// Set once the person picks a time zone themselves; the location no longer decides it then.
    var timeZoneIsManual = false

    /// A new park gets a guided walk-through; an existing one is edited freely.
    let isGuided: Bool
    /// Saved or discarded: the draft file is gone and must not be written again.
    private var isFinished = false

    @ObservationIgnored private let store = ParkDraftStore(directory: AppConstants.localPhoneParkDraftsRoot)
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(original: Park?, resuming draft: ParkEditDraft?) {
        let blank = Park(
            id: "",
            name: "",
            location: ParkCoordinate(lat: 0, lon: 0),
            timezone: TimeZone.current.identifier
        )
        initial = original ?? blank
        editsParkID = original?.id ?? draft?.editsParkID
        draftID = draft?.id ?? (original.map { ParkEditDraft.editID(forPark: $0.id) } ?? ParkEditDraft.newID())
        park = draft?.park ?? original ?? blank
        isGuided = (original == nil) && (draft?.editsParkID == nil)
        step = min(max(draft?.step ?? 0, 0), ParkEditorStep.guided.count - 1)
        timeZoneIsManual = original != nil || draft != nil
    }

    // MARK: State

    /// The park as it would be written: cleaned and tidied.
    var finalized: Park { ParkDraft.finalized(park) }

    var isDirty: Bool { finalized != ParkDraft.finalized(initial) }

    /// Everything that stops saving right now.
    var issues: [ParkDraft.Issue] { ParkDraft.validate(finalized) }

    var currentStep: ParkEditorStep { ParkEditorStep.guided[step] }

    func issues(on page: ParkEditorPage) -> [ParkDraft.Issue] {
        issues.filter { page.sections.contains($0.section) }
    }

    func isFilled(_ page: ParkEditorPage) -> Bool {
        page.sections.contains { ParkDraft.isFilled($0, in: finalized) }
    }

    // MARK: Navigation

    func goToNext() { step = min(step + 1, ParkEditorStep.guided.count - 1) }
    func goToPrevious() { step = max(step - 1, 0) }

    func jump(to page: ParkEditorPage) {
        if isGuided {
            path = []
            step = ParkEditorStep.guided.firstIndex(of: .page(page)) ?? step
        } else {
            path = [.page(page)]
        }
    }

    func askToDelete(title: String, message: String, perform: @escaping () -> Void) {
        deletion = ParkEditorDeletion(title: title, message: message, perform: perform)
    }

    // MARK: Draft on disk

    /// Called on every change: writes the draft shortly after the last edit, so nothing is lost when
    /// the app is closed, killed or interrupted.
    func scheduleDraftSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.saveDraftNow()
        }
    }

    func saveDraftNow() {
        saveTask?.cancel()
        guard !isFinished else { return }
        guard isDirty else {
            store.delete(id: draftID)
            return
        }
        let draft = ParkEditDraft(
            id: draftID,
            editsParkID: editsParkID,
            park: park,
            step: isGuided ? step : nil
        )
        do {
            try store.save(draft)
        } catch {
            WakeLog.error(.store, "park draft save: \(error.localizedDescription)")
        }
        ParkDraftsController.shared.reload()
    }

    func discardDraft() {
        saveTask?.cancel()
        isFinished = true
        store.delete(id: draftID)
        ParkDraftsController.shared.reload()
    }

    // MARK: Saving the park

    /// Writes the park and removes the draft. Throws what the store throws.
    func save() throws {
        var result = finalized
        if result.id.isEmpty { result.id = ParkStore.shared.newParkID(for: result.name) }
        try ParkStore.shared.save(result)
        discardDraft()
    }
}

/// The unfinished parks, for the list in the Parks tab.
@Observable
@MainActor
final class ParkDraftsController {
    static let shared = ParkDraftsController()

    private(set) var drafts: [ParkEditDraft] = []

    @ObservationIgnored private let store = ParkDraftStore(directory: AppConstants.localPhoneParkDraftsRoot)

    func reload() {
        drafts = store.all()
    }

    /// The unsaved edit of an existing park, if there is one.
    func draft(editing parkID: String) -> ParkEditDraft? {
        drafts.first { $0.editsParkID == parkID }
    }

    func delete(_ draft: ParkEditDraft) {
        store.delete(id: draft.id)
        reload()
    }
}
