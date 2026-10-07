import Foundation

/// Where a flag is grouped in the picker (and which tint it gets).
public enum SetFlagKind: Int, Sendable, CaseIterable {
    case startFinish
    case trick
    case custom
}

/// Self-notes on a set: opaque strings, never a closed enum. Presets are known snake_case codes the
/// UI localizes; any other string is a custom label shown verbatim and must round-trip untouched.
public enum SetFlags {
    public static let startFinish = ["cable_stop", "clean_exit", "clean_start", "failed_start", "wipeout"]
    public static let tricks = ["failed_jump", "new_trick", "successful_jump"]
    public static let maxLength = 24

    public static func kind(of flag: String) -> SetFlagKind {
        if startFinish.contains(flag) { return .startFinish }
        if tricks.contains(flag) { return .trick }
        return .custom
    }

    /// Presets of one kind (empty for `.custom`).
    public static func presets(of kind: SetFlagKind) -> [String] {
        switch kind {
        case .startFinish: startFinish
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
    public static func toggling(_ flag: String, in flags: [String]) -> [String] {
        var result = flags
        if let index = result.firstIndex(where: { $0.caseInsensitiveCompare(flag) == .orderedSame }) {
            result.remove(at: index)
        } else {
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

    /// Manifest key for a set (`SetSegmentStats.index`).
    public static func key(forSet index: Int) -> String { String(index) }
}

/// Unsaved flag edits for one session, over what the manifest already holds. Codable so the phone
/// can keep it across backgrounding and force-quit.
public struct SetFlagDraft: Codable, Equatable, Sendable {
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

    /// Same draft re-based on freshly saved flags (e.g. after "Done"): no longer dirty.
    public mutating func markSaved() { base = draft }

    public mutating func discard() { draft = base }

    private static func clean(_ flags: [String: [String]]) -> [String: [String]] {
        flags.filter { !$0.value.isEmpty }
    }
}
