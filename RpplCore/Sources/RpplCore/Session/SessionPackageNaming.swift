import Foundation

/// Human-readable session package folder names for Files / iCloud Drive.
///
/// Canonical identity stays `manifest.sessionId` (UUID). Folder name is display-only:
/// `YYYY-MM-DD - City` with ` (2)`, ` (3)`, … on collision.
///
/// Manual renames are preserved: the store discovers packages via `manifest.json`.
public enum SessionPackageNaming {
    public static let unknownCity = "Unknown"

    /// Local calendar day of `startedAt` plus display city: `2026-06-01 - Rotterdam`.
    public static func baseFolderName(
        startedAt: Date,
        cityName: String?,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        "\(dateString(startedAt: startedAt, timeZone: timeZone, locale: locale)) - \(displayCity(cityName))"
    }

    /// Picks `base` or `base (2)` / `base (3)` / … not present in `existingNames`.
    public static func uniqueFolderName(base: String, existingNames: Set<String>) -> String {
        if !existingNames.contains(base) {
            return base
        }
        var n = 2
        while existingNames.contains("\(base) (\(n))") {
            n += 1
        }
        return "\(base) (\(n))"
    }

    /// City for folder titles; empty / nil → `Unknown`. Strips path separators.
    public static func displayCity(_ cityName: String?) -> String {
        let trimmed = (cityName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return unknownCity }

        var scalars: [Unicode.Scalar] = []
        scalars.reserveCapacity(trimmed.unicodeScalars.count)
        var pendingSpace = false
        for scalar in trimmed.unicodeScalars {
            if scalar == "/" || scalar == "\\" {
                pendingSpace = true
                continue
            }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                pendingSpace = true
                continue
            }
            if pendingSpace, !scalars.isEmpty {
                scalars.append(" ")
                pendingSpace = false
            }
            scalars.append(scalar)
        }
        let cleaned = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? unknownCity : cleaned
    }

    /// True when the folder looks app-owned (canonical pattern or legacy bare UUID).
    public static func isAppGenerated(_ folderName: String) -> Bool {
        isLegacyUUIDFolder(folderName) || matchesCanonicalPattern(folderName)
    }

    /// Legacy layout: folder name equals a UUID (historically == `sessionId`).
    public static func isLegacyUUIDFolder(_ folderName: String) -> Bool {
        UUID(uuidString: folderName) != nil
    }

    /// `YYYY-MM-DD - City` or `YYYY-MM-DD - City (N)`.
    public static func matchesCanonicalPattern(_ folderName: String) -> Bool {
        let pattern = #"^\d{4}-\d{2}-\d{2} - .+?(?: \(\d+\))?$"#
        return folderName.range(of: pattern, options: .regularExpression) != nil
    }

    /// Rejects empty names and path traversal before building a package URL.
    public static func validateFolderName(_ folderName: String) throws {
        guard !folderName.isEmpty else {
            throw SessionStoreError.invalidSessionId(folderName)
        }
        if folderName.contains("/") || folderName.contains("\\") {
            throw SessionStoreError.invalidSessionId(folderName)
        }
        if folderName.contains("..") {
            throw SessionStoreError.invalidSessionId(folderName)
        }
        if folderName.hasPrefix(".") {
            throw SessionStoreError.invalidSessionId(folderName)
        }
    }

    /// Package directory under `rootURL` for a validated folder name.
    public static func packageDirectory(folderName: String, rootURL: URL) throws -> URL {
        try validateFolderName(folderName)
        let root = rootURL.standardizedFileURL
        let resolved = root.appendingPathComponent(folderName, isDirectory: true).standardizedFileURL
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard resolved.path.hasPrefix(rootPrefix) else {
            throw SessionStoreError.invalidSessionId(folderName)
        }
        return resolved
    }

    // MARK: - Private

    private static func dateString(
        startedAt: Date,
        timeZone: TimeZone,
        locale: Locale
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        _ = locale // reserved for future localized titles; date stays ISO-like
        return formatter.string(from: startedAt)
    }
}
