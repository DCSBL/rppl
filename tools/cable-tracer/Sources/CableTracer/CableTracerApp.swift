import SwiftUI

@main
struct CableTracerApp: App {
    @State private var model = EditorModel()

    var body: some Scene {
        WindowGroup("Cable Tracer") {
            ContentView(model: model)
                .frame(minWidth: 1100, minHeight: 700)
                .task { model.openDefaultDirectory() }
        }
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Save Park") { model.save() }
                    .keyboardShortcut("s")
                    .disabled(!model.isDirty)
            }
            CommandGroup(after: .newItem) {
                Button("Open Parks Folder…") { model.chooseDirectory() }
                    .keyboardShortcut("o")
            }
        }
    }
}
