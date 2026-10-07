import Foundation

/// Mirrors the editor's form sections, for a section-level "these parts changed" summary.
public enum ParkSection: String, CaseIterable, Sendable {
    case basics
    case location
    case contact
    case about
    case cables
    case opening
    case prices
    case links
}

public enum ParkDiff {
    /// Which editor sections differ between `original` and `edited`. Not a field-by-field diff.
    public static func changedSections(from original: Park, to edited: Park) -> [ParkSection] {
        var sections: [ParkSection] = []
        if original.name != edited.name || original.author != edited.author || original.timezone != edited.timezone {
            sections.append(.basics)
        }
        if original.location != edited.location || original.address != edited.address {
            sections.append(.location)
        }
        if original.phone != edited.phone || original.email != edited.email || original.website != edited.website {
            sections.append(.contact)
        }
        if original.description != edited.description || original.facilities != edited.facilities {
            sections.append(.about)
        }
        if original.cables != edited.cables {
            sections.append(.cables)
        }
        if original.opening != edited.opening {
            sections.append(.opening)
        }
        if original.prices != edited.prices {
            sections.append(.prices)
        }
        if original.links != edited.links {
            sections.append(.links)
        }
        return sections
    }
}
