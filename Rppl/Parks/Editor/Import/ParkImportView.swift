import PhotosUI
import RpplCore
import SwiftUI

/// Fills in a park from a website or a screenshot, on the phone. Nothing is written until the person
/// picks suggestions and taps "Add selected"; suggestions that cannot be found in the source start off.
struct ParkImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ParkImportModel
    @State private var address = ""
    @State private var photo: PhotosPickerItem?

    init(session: ParkEditorSession) {
        _model = State(initialValue: ParkImportModel(session: session))
    }

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                if model.isWorking { progressSection }
                if !model.notes.isEmpty { notesSection }
                suggestionsSection
                if !model.questions.isEmpty, !model.isWorking { questionsSection }
            }
            .navigationTitle("Fill in from a source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add selected") {
                        model.apply()
                        dismiss()
                    }
                    .disabled(model.selected.isEmpty || model.isWorking)
                }
            }
            .onChange(of: photo) { _, item in
                Task { await load(item) }
            }
        }
    }

    // MARK: Sections

    private var sourceSection: some View {
        Section {
            TextField("Website address", text: $address)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit(readWebsite)
            Button("Read website", action: readWebsite)
                .disabled(model.isWorking || address.trimmingCharacters(in: .whitespaces).isEmpty)
            PhotosPicker(selection: $photo, matching: .images) {
                Label("Add screenshot", systemImage: "photo")
            }
            .disabled(model.isWorking)
        } header: {
            Text("Source")
        } footer: {
            Text("The text is read on this iPhone. Only the website you name is opened. Check every suggestion before you add it.")
        }
    }

    private var progressSection: some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                progressText
            }
        }
    }

    private var progressText: Text {
        switch model.phase {
        case .idle, .fetching: Text("Opening the page…")
        case .recognizing: Text("Reading the screenshot…")
        case .reading(let part, let total): Text("Reading part \(part) of \(total)…")
        }
    }

    private var notesSection: some View {
        Section {
            ForEach(model.notes, id: \.self) { note in
                Label(noteText(note), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var suggestionsSection: some View {
        if !model.items.isEmpty {
            Section {
                ForEach(model.items) { item in
                    Toggle(isOn: isOn(item.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fieldName(item.field))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.title)
                            if let previous = item.previous {
                                Text("Now: \(previous)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            if item.level != .verified {
                                Label("Not found as written in the source", systemImage: "exclamationmark.circle")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            } header: {
                Text("Suggestions")
            }
        } else if model.hasRead, !model.isWorking {
            Section {
                Text("Nothing new found.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var questionsSection: some View {
        Section {
            ForEach(model.questions) { question in
                Label(questionText(question), systemImage: "questionmark.circle")
            }
        } footer: {
            Text("Add another page or screenshot to look further.")
        }
    }

    // MARK: Text

    private func fieldName(_ field: ParkImportField) -> LocalizedStringKey {
        switch field {
        case .phone: "Phone"
        case .email: "Email"
        case .website: "Website"
        case .address: "Address"
        case .links: "Links"
        case .prices: "Prices"
        case .facilities: "Facilities"
        }
    }

    private func questionText(_ question: ParkImportQuestion) -> LocalizedStringKey {
        switch question {
        case .missing(.phone): "No phone number found"
        case .missing(.email): "No email address found"
        case .missing(.address): "No address found"
        case .missing: "No prices found"
        }
    }

    private func noteText(_ note: ParkImportModel.Note) -> LocalizedStringKey {
        switch note {
        case .badAddress: "That is not a web address."
        case .unreadablePage: "Could not open that page."
        case .unreadableImage: "Could not read text in that image."
        case .modelSkipped: "The model could not read part of the text."
        }
    }

    // MARK: Actions

    private func isOn(_ id: String) -> Binding<Bool> {
        Binding(
            get: { model.selected.contains(id) },
            set: { isOn in
                if isOn { model.selected.insert(id) } else { model.selected.remove(id) }
            }
        )
    }

    private func readWebsite() {
        let text = address
        Task { await model.addWebsite(text) }
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        defer { photo = nil }
        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
            await model.addScreenshot(image)
        } else {
            await model.addScreenshot(UIImage())
        }
    }
}
