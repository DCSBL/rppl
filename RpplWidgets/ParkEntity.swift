import AppIntents
import RpplCore

/// A cable park the widget can show. Resolved from the same bundled + user park files the app reads.
struct ParkEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Park"
    static let defaultQuery = ParkEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(park: Park) {
        id = park.id
        name = park.name
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
        ParkCatalog.load(userRoot: AppConstants.localPhoneParksRoot)
    }

    static func park(id: String) -> Park? {
        parks().first { $0.id == id }
    }
}

struct SelectParkIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Select park"
    static let description = IntentDescription("Choose the cable park to show opening hours for.")

    @Parameter(title: "Park")
    var park: ParkEntity?
}
