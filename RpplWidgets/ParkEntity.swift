import AppIntents
import RpplCore

/// A cable park the widget can show. Resolved from the same bundled + user park files the app reads.
struct ParkEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Park"
    static let defaultQuery = ParkEntityQuery()

    var id: String
    var name: String
    /// "Knokke-Heist, Belgium": shown under the name in the picker.
    var place: String?

    var displayRepresentation: DisplayRepresentation {
        if let place { return DisplayRepresentation(title: "\(name)", subtitle: "\(place)") }
        return DisplayRepresentation(title: "\(name)")
    }

    init(park: Park) {
        id = park.id
        name = park.name
        place = park.placeSubtitle()
    }
}

struct ParkEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ParkEntity] {
        ParkWidgetStore.parks().filter { identifiers.contains($0.id) }.map(ParkEntity.init)
    }

    func entities(matching string: String) async throws -> [ParkEntity] {
        ParkSearch.filter(ParkWidgetStore.parks(), query: string).map(ParkEntity.init)
    }

    func suggestedEntities() async throws -> [ParkEntity] {
        ParkWidgetStore.parks().map(ParkEntity.init)
    }
}

enum ParkWidgetStore {
    static func parks() -> [Park] {
        ParkCatalog.loadApp()
    }

    static func park(id: String) -> Park? {
        parks().first { $0.id == id }
    }

    static func snapshot() -> ParkWidgetSnapshot { ParkWidgetSnapshotStore.load() }

    /// Fallback while no park is picked; `nil` until the app has written visit counts.
    static func mostVisited() -> Park? {
        snapshot().mostVisited(in: parks())
    }
}

struct SelectParkIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Select park"
    static let description = IntentDescription("Choose the cable park to show opening hours for. Empty shows your most visited park.")

    @Parameter(title: "Park")
    var park: ParkEntity?
}
