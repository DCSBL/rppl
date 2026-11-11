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
                if !model.knownSources.isEmpty { rescanSection }
                websiteSection
                screenshotSection
                if !model.hasRead, !model.isWorking { capabilitiesSection }
                if model.isWorking { progressSection }
                if !model.trace.isEmpty { traceSection }
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
            // An existing park is read again from where its data came from, without asking for links.
            .task { await model.rescan() }
        }
    }

    // MARK: Sections

    private var rescanSection: some View {
        Section {
            ForEach(model.knownSources, id: \.self) { source in
                Text(verbatim: source)
                    .font(.footnote)
                    .lineLimit(1)
            }
            Button {
                Task { await model.rescan() }
            } label: {
                Label("Rescan known sources", systemImage: "arrow.clockwise")
            }
            .disabled(model.isWorking)
        } header: {
            Text("Known sources")
        } footer: {
            Text("Reads these pages again and looks for newer opening hours, prices and contact details.")
        }
    }

    private var websiteSection: some View {
        Section {
            TextField("Website address", text: $address)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(searchWebsite)
            Button(action: searchWebsite) {
                Label("Search website", systemImage: "magnifyingglass")
            }
            .disabled(model.isWorking || address.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("Website")
        } footer: {
            Text("Reads the page and follows links to the pages with opening hours, prices and contact details.")
        }
    }

    private var screenshotSection: some View {
        Section {
            PhotosPicker(selection: $photo, matching: .images) {
                Label("Add screenshot", systemImage: "photo")
            }
            .disabled(model.isWorking)
        } header: {
            Text("Screenshot")
        } footer: {
            Text("For a post on Instagram or a page of a PDF. The text is read on this iPhone.")
        }
    }

    private var capabilitiesSection: some View {
        Section {
            Label("Phone, email and address", systemImage: "phone")
            Label("Opening hours", systemImage: "clock")
            Label("Prices", systemImage: "eurosign.circle")
            Label("Website and social links", systemImage: "link")
            Label("Events and closures", systemImage: "calendar")
            Label("Facilities", systemImage: "list.bullet")
        } header: {
            Text("Can be filled in")
        } footer: {
            Text("Cables and the location stay manual.")
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
        case .idle: Text("Searching…")
        case .fetching(let label): Text("Reading \(label)…")
        case .recognizing: Text("Reading the screenshot…")
        case .reading(let part, let total): Text("Reading part \(part) of \(total)…")
        }
    }

    private var traceSection: some View {
        Section {
            ForEach(model.trace) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: entry.label)
                    traceDetail(entry)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Pages read")
        }
    }

    private func traceDetail(_ entry: ParkImportTraceEntry) -> Text {
        if entry.failed { return Text("Could not open that page.") }
        if entry.found.isEmpty { return Text("Nothing found here") }
        return Text(verbatim: entry.found.map { String(localized: fieldName($0)) }.joined(separator: ", "))
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
                            Text(verbatim: item.title)
                            if let detail = item.detail, !detail.isEmpty {
                                Text(verbatim: detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
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
            } footer: {
                Text("Check every suggestion before you add it.")
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

    private func fieldName(_ field: ParkImportField) -> LocalizedStringResource {
        switch field {
        case .phone: "Phone"
        case .email: "Email"
        case .website: "Website"
        case .address: "Address"
        case .links: "Links"
        case .prices: "Prices"
        case .facilities: "Facilities"
        case .opening: "Opening hours"
        case .events: "Events and closures"
        }
    }

    private func questionText(_ question: ParkImportQuestion) -> LocalizedStringKey {
        switch question {
        case .missing(.phone): "No phone number found"
        case .missing(.email): "No email address found"
        case .missing(.address): "No address found"
        case .missing(.opening): "No opening hours found"
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

    private func searchWebsite() {
        let text = address
        Task { await model.searchWebsite(text) }
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
