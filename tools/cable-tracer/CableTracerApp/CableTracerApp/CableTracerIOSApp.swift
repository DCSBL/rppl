import CableTracerUI
import SwiftUI

/// Simulator build of the tracer: the same editor as the macOS executable, so the UI can be
/// driven and screenshotted with `simctl` on a Mac without screen-recording permission.
/// Pass the host parks folder as `--parks <dir>` (launch argument) or `CABLE_TRACER_PARKS`.
@main
struct CableTracerIOSApp: App {
    @State private var model = EditorModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .task {
                    model.defaultExportDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
                        .appendingPathComponent("training-set", isDirectory: true)
                    model.openDefaultDirectory()
                }
        }
    }
}
