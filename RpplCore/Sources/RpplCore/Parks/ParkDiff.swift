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

/// Line-level difference between two YAML documents. Line numbers are 1-based: `removed` refers to
/// the original text, `added` to the edited text.
public struct ParkLineDiff: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public let number: Int
        public let text: String
    }

    public let removed: [Line]
    public let added: [Line]

    public var isEmpty: Bool { removed.isEmpty && added.isEmpty }

    /// Git-style unified-ish text (`-`/`+` lines with line numbers), suitable for base64 transport.
    public var patchText: String {
        (removed.map { "-\($0.number): \($0.text)" } + added.map { "+\($0.number): \($0.text)" })
            .joined(separator: "\n")
    }
}

public enum ParkDiff {
    /// Which lines of `originalYAML` were removed and which lines of `editedYAML` were added.
    public static func lineDiff(from originalYAML: String, to editedYAML: String) -> ParkLineDiff {
        let old = originalYAML.components(separatedBy: "\n")
        let new = editedYAML.components(separatedBy: "\n")
        var removed: [ParkLineDiff.Line] = []
        var added: [ParkLineDiff.Line] = []
        for change in new.difference(from: old) {
            switch change {
            case let .remove(offset, element, _): removed.append(.init(number: offset + 1, text: element))
            case let .insert(offset, element, _): added.append(.init(number: offset + 1, text: element))
            }
        }
        return ParkLineDiff(
            removed: removed.sorted { $0.number < $1.number },
            added: added.sorted { $0.number < $1.number }
        )
    }
}
