import Foundation
import RpplCore

extension MastLabelStore {
    /// `<repo>/tools/cable-tracer/mast-labels.json` for a parks folder inside the repo; next to the
    /// parks folder otherwise (never inside it: the app bundles that folder).
    public static func defaultFile(parksDirectory: URL) -> URL {
        var url = parksDirectory.standardizedFileURL
        for _ in 0..<8 {
            let tool = url.appendingPathComponent("tools/cable-tracer", isDirectory: true)
            if FileManager.default.fileExists(atPath: tool.path) { return tool.appendingPathComponent(fileName) }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return parksDirectory.deletingLastPathComponent().appendingPathComponent(fileName)
    }
}
