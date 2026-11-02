import AppKit
import CableTracerCore
import CableTracerUI
import Foundation
import RpplCore

// `cable-tracer --export-training-set <dir> [--parks <parks dir>]` renders the training set
// without opening a window (MapKit snapshots still need a logged-in macOS session).
// Anything else launches the app.
let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--export-training-set"), arguments.indices.contains(flag + 1) {
    let output = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
    let parksDirectory: URL
    if let parksFlag = arguments.firstIndex(of: "--parks"), arguments.indices.contains(parksFlag + 1) {
        parksDirectory = URL(fileURLWithPath: arguments[parksFlag + 1], isDirectory: true)
    } else if let located = ParkWorkspace.locateBundledParks() {
        parksDirectory = located
    } else {
        FileHandle.standardError.write(Data("Cannot find the parks directory; pass --parks <dir>\n".utf8))
        exit(2)
    }
    let tracedOnly = !arguments.contains("--all-parks")
    Task { @MainActor in
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let parks = ParkWorkspace(directory: parksDirectory).load()
            var rows = TrainingSet.rows(parks: parks, tracedOnly: tracedOnly)
            print("Exporting \(rows.count) parks from \(parksDirectory.path) to \(output.path)")
            for index in rows.indices {
                let started = Date()
                let snapshots = try await SnapshotExporter.export(row: rows[index], into: output)
                rows[index].snapshot = snapshots.overview
                rows[index].detailSnapshot = snapshots.detail
                print(String(format: "  %@ (%.1fs)", rows[index].parkID, Date().timeIntervalSince(started)))
            }
            try TrainingSet.encode(rows).write(to: output.appendingPathComponent("training-set.json"))
            print("Done: training-set.json + \(rows.count) snapshots")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Export failed: \(error)\n".utf8))
            exit(1)
        }
    }
    RunLoop.main.run()
} else {
    CableTracerApp.main()
}
