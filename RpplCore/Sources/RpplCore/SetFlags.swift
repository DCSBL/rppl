import Foundation

/// Where a flag is grouped in the picker (and which tint it gets). Declaration order is display order.
public enum SetFlagKind: Int, Sendable, CaseIterable {
    case start
    case exit
    case trick
    case custom

    /// Start and exit hold at most one flag per set; tricks and custom flags stack.
    public var isSingleChoice: Bool { self == .start || self == .exit }
}

/// Self-notes on a set: opaque strings, never a closed enum. Presets are known snake_case codes the
/// UI localizes; any other string is a custom label shown verbatim and must round-trip untouched.
public enum SetFlags {
    public static let starts = [
        "clean_start", "failed_start", "jump_start", "nollie_start", "other_start", "sit_start", "slide_start"
    ]
    public static let exits = ["cable_snap", "clean_exit", "dry_exit", "fall", "wipeout"]
    public static let tricks = [
        "180", "360", "backroll", "box", "failed_jump", "frontroll", "kicker", "new_trick", "ollie", "rail",
        "raley", "switch", "tantrum"
    ]
    public static let maxLength = 24

    public static func kind(of flag: String) -> SetFlagKind {
        if starts.contains(flag) { return .start }
        if exits.contains(flag) { return .exit }
        if tricks.contains(flag) { return .trick }
        return .custom
    }

    /// Presets of one kind (empty for `.custom`).
    public static func presets(of kind: SetFlagKind) -> [String] {
        switch kind {
        case .start: starts
        case .exit: exits
        case .trick: tricks
        case .custom: []
        }
    }

    /// Typed custom text to a stored flag: trimmed, whitespace collapsed, capped. Text that spells a
    /// preset ("Clean start") becomes its code. Nil when empty.
    public static func normalized(custom text: String) -> String? {
        let words = text.split(whereSeparator: \.isWhitespace)
        let joined = String(words.joined(separator: " ").prefix(maxLength))
            .trimmingCharacters(in: .whitespaces)
        guard !joined.isEmpty else { return nil }
        let code = joined.lowercased().replacingOccurrences(of: " ", with: "_")
        return kind(of: code) == .custom ? joined : code
    }

    /// Flags with `flag` toggled (case-insensitive match), grouped by kind, then alphabetical by code.
    /// Switching on a start or exit flag replaces the one already chosen for that kind.
    public static func toggling(_ flag: String, in flags: [String]) -> [String] {
        var result = flags
        if let index = result.firstIndex(where: { $0.caseInsensitiveCompare(flag) == .orderedSame }) {
            result.remove(at: index)
        } else {
            let kind = kind(of: flag)
            if kind.isSingleChoice { result.removeAll { Self.kind(of: $0) == kind } }
            result.append(flag)
        }
        return ordered(result)
    }

    public static func ordered(_ flags: [String]) -> [String] {
        flags.sorted {
            let (a, b) = (kind(of: $0).rawValue, kind(of: $1).rawValue)
            return a != b ? a < b : $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    public static func contains(_ flag: String, in flags: [String]) -> Bool {
        flags.contains { $0.caseInsensitiveCompare(flag) == .orderedSame }
    }

    /// Flags for sets 1...count only (a manual session whose set count went down).
    public static func trimmed(_ flags: [String: [String]], toSetCount count: Int) -> [String: [String]] {
        flags.filter { key, value in
            guard let index = Int(key) else { return false }
            return index >= 1 && index <= count && !value.isEmpty
        }
    }

    /// Manifest key for a set (`SetSegmentStats.index`).
    public static func key(forSet index: Int) -> String { String(index) }
}

/// Unsaved flag edits for one session, over what the manifest already holds.
public struct SetFlagDraft: Equatable, Sendable {
    public private(set) var base: [String: [String]]
    public private(set) var draft: [String: [String]]

    public init(saved: [String: [String]]?) {
        let clean = Self.clean(saved ?? [:])
        base = clean
        draft = clean
    }

    public var isDirty: Bool { draft != base }

    /// Draft without empty sets: what gets stored on "Done".
    public var result: [String: [String]] { draft }

    public func flags(forSet index: Int) -> [String] { draft[SetFlags.key(forSet: index)] ?? [] }

    public mutating func toggle(_ flag: String, forSet index: Int) {
        let key = SetFlags.key(forSet: index)
        let updated = SetFlags.toggling(flag, in: draft[key] ?? [])
        draft[key] = updated.isEmpty ? nil : updated
    }

    public mutating func discard() { draft = base }

    private static func clean(_ flags: [String: [String]]) -> [String: [String]] {
        flags.filter { !$0.value.isEmpty }
    }
}
