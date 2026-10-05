import Foundation

/// Decodes the bundled example session in the background so opening it is instant.
///
/// The file is read once and kept un-shifted; each `load` moves the timeline to end at `now`,
/// so the example never reads as hours old after a long wait on the empty state.
public final class ExampleSessionPreload: Sendable {
    /// Bundled file name (without extension), shared by the iPhone and Watch targets.
    public static let resourceName = "FBDC7D8C-8FEA-47B6-911B-00E94A8A496C"

    /// App-wide instance; the first access starts decoding the bundled file.
    public static let shared = ExampleSessionPreload(packageURL: bundledURL())

    private let decoded: Task<SessionTransferPackage, Error>

    init(packageURL: URL?) {
        decoded = Task.detached(priority: .utility) {
            guard let packageURL else {
                throw SessionStoreError.ioFailure("Bundled example session missing")
            }
            let data = try SessionImportLimits.readBoundedFile(at: packageURL)
            return try SessionImportLimits.decodeTransferPackage(from: data)
        }
    }

    /// Call when the empty state appears; a no-op once started.
    public static func warmUp() {
        _ = shared
    }

    public func load(now: Date = Date()) async throws -> SessionLoadBundle {
        try SessionLoader.loadExample(package: try await decoded.value, now: now)
    }

    static func bundledURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: resourceName, withExtension: "json", subdirectory: "Exports")
            ?? bundle.url(forResource: resourceName, withExtension: "json")
    }
}
