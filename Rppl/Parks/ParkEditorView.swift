import CoreLocation
import MapKit
import RpplCore
import SwiftUI

struct ParkEditorView: View {
    /// nil creates a new custom park.
    let original: Park?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Park
    private let initial: Park
    @State private var location = ParksLocationProvider()
    @State private var tracing: Int?
    @State private var pickingLocation = false
    @State private var confirmDiscard = false
    @State private var saveError: String?

    init(original: Park?, onSaved: @escaping () -> Void) {
        self.original = original
        self.onSaved = onSaved
        let start = original ?? Park(
            id: "",
            name: "",
            location: ParkCoordinate(lat: 0, lon: 0),
            timezone: TimeZone.current.identifier
        )
        initial = start
        _draft = State(initialValue: start)
    }

    /// Where the trace map opens: the park pin, else the user's position, never 0,0.
    private var traceCenter: ParkCoordinate {
        ParkDraft.isValid(draft.location) ? draft.location : (location.coordinate ?? draft.location)
    }

    private var issues: [ParkDraft.Issue] { ParkDraft.validate(draft) }
    private var isDirty: Bool { draft != initial && !(original == nil && onlyAutoLocationChanged) }
    private var onlyAutoLocationChanged: Bool {
        var probe = draft
        probe.location = initial.location
        return probe == initial
    }

    var body: some View {
        NavigationStack {
            Form {
                basicsSection
                locationSection
                contactSection
                aboutSection
                cablesSection
                openingSection
                pricesSection
                linksSection
            }
            .navigationTitle(original == nil ? Text("New park") : Text("Edit park"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isDirty ? (confirmDiscard = true) : dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!issues.isEmpty)
                }
            }
            .confirmationDialog("Discard changes?", isPresented: $confirmDiscard) {
                Button("Discard", role: .destructive) { dismiss() }
            }
            .alert("Could not save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
            .fullScreenCover(item: Binding(get: { tracing.map(TraceTarget.init) }, set: { tracing = $0?.index })) { target in
                CableTraceView(cable: cableBinding(target.index), center: traceCenter)
            }
            .sheet(isPresented: $pickingLocation) {
                LocationPickerView(coordinate: $draft.location)
            }
            .task { location.refresh() }
            .interactiveDismissDisabled(isDirty)
            .onChange(of: location.coordinate) { _, fix in
                // A new park has no location yet: default it to where the user is.
                if let fix, original == nil, !ParkDraft.isValid(draft.location) { draft.location = fix }
            }
        }
        .tint(Color.rpplAccent)
    }

    // MARK: Sections

    private var basicsSection: some View {
        Section("Park") {
            TextField("Name", text: $draft.name)
            TextField("Author (credit)", text: text($draft.author))
                .textInputAutocapitalization(.words)
            Picker("Time zone", selection: Binding(
                get: { draft.timezone ?? TimeZone.current.identifier },
                set: { draft.timezone = $0 }
            )) {
                ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
            }
            if !issues.isEmpty {
                ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                    Label(issueText(issue), systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var locationSection: some View {
        Section("Location") {
            TextField("Address", text: text($draft.address), axis: .vertical)
            coordinateField("Latitude", value: $draft.location.lat)
            coordinateField("Longitude", value: $draft.location.lon)
            Button("Use current location", systemImage: "location") {
                if let here = location.coordinate { draft.location = here } else { location.refresh() }
            }
            .task { location.refresh() }
            Button("Pick on map", systemImage: "mappin.and.ellipse") { pickingLocation = true }
        }
    }

    private var contactSection: some View {
        Section("Contact") {
            TextField("Phone", text: text($draft.phone)).keyboardType(.phonePad)
            TextField("Email", text: text($draft.email))
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Website", text: text($draft.website))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private var aboutSection: some View {
        Section("About") {
            TextField("Description", text: text($draft.description), axis: .vertical)
                .lineLimit(2...8)
            StringListEditor(title: "Facilities", addLabel: "Add facility", items: Binding(
                get: { draft.facilities ?? [] },
                set: { draft.facilities = $0.isEmpty ? nil : $0 }
            ))
        }
    }

    private var cablesSection: some View {
        Section("Cables") {
            ForEach((draft.cables ?? []).indices, id: \.self) { index in
                DisclosureGroup {
                    TextField("Name", text: text(cableField(index, \.name)))
                    Picker("Direction", selection: Binding(
                        get: { draft.cables?[index].direction?.rawValue ?? "cw" },
                        set: { draft.cables?[index].direction = ParkCableDirection(rawValue: $0) }
                    )) {
                        Text("Clockwise").tag("cw")
                        Text("Counter-clockwise").tag("ccw")
                        Text("2D").tag("2d")
                    }
                    TextField("Length (m, optional)", value: cableField(index, \.lengthM), format: .number)
                        .keyboardType(.decimalPad)
                    TextField("Description", text: text(cableField(index, \.description)), axis: .vertical)
                    Button("Trace on map", systemImage: "scribble.variable") { tracing = index }
                } label: {
                    VStack(alignment: .leading) {
                        Text(draft.cables?[index].name ?? String(localized: "Cable \(index + 1)"))
                        Text("\(draft.cables?[index].points?.count ?? 0) points")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { draft.cables?.remove(atOffsets: $0) }
            Button("Add cable", systemImage: "plus") {
                var cables = draft.cables ?? []
                cables.append(ParkCable(direction: .clockwise))
                draft.cables = cables
                tracing = cables.count - 1
            }
        }
    }

    private var openingSection: some View {
        Section("Opening") {
            Picker("Booking", selection: Binding(
                get: { draft.opening?.booking ?? "" },
                set: { value in updateOpening { $0.booking = value.isEmpty ? nil : value } }
            )) {
                Text("Not set").tag("")
                Text("Required").tag("required")
                Text("Optional").tag("optional")
                Text("None").tag("none")
            }
            Toggle("Numbered blocks", isOn: Binding(
                get: { draft.opening?.numbered ?? true },
                set: { value in updateOpening { $0.numbered = value } }
            ))
            TextField("Note", text: Binding(
                get: { draft.opening?.note ?? "" },
                set: { value in updateOpening { $0.note = value.isEmpty ? nil : value } }
            ), axis: .vertical)
            ForEach((draft.opening?.rules ?? []).indices, id: \.self) { index in
                RuleEditor(rule: Binding(
                    get: { draft.opening?.rules?[index] ?? ParkOpeningRule(open: "09:00", close: "18:00") },
                    set: { value in updateOpening { $0.rules?[index] = value } }
                ))
            }
            .onDelete { offsets in updateOpening { $0.rules?.remove(atOffsets: offsets) } }
            Button("Add opening hours", systemImage: "plus") {
                updateOpening { $0.rules = ($0.rules ?? []) + [ParkOpeningRule(open: "09:00", close: "18:00")] }
            }
            ForEach((draft.opening?.slots ?? []).indices, id: \.self) { index in
                SlotEditor(slot: Binding(
                    get: { draft.opening?.slots?[index] ?? ParkSlot(id: "", start: "09:00", end: "10:00") },
                    set: { value in updateOpening { $0.slots?[index] = value } }
                ))
            }
            .onDelete { offsets in updateOpening { $0.slots?.remove(atOffsets: offsets) } }
            Button("Add block", systemImage: "plus") {
                updateOpening {
                    let next = ($0.slots ?? []).count + 1
                    $0.slots = ($0.slots ?? []) + [ParkSlot(id: "\(next)", start: "09:00", end: "10:00")]
                }
            }
        }
    }

    private var pricesSection: some View {
        Section("Prices") {
            ForEach((draft.prices ?? []).indices, id: \.self) { index in
                VStack(alignment: .leading) {
                    TextField("Name", text: priceBinding(index, \.name))
                    TextField("Price", text: priceBinding(index, \.price))
                    TextField("Note", text: Binding(
                        get: { draft.prices?[index].note ?? "" },
                        set: { draft.prices?[index].note = $0.isEmpty ? nil : $0 }
                    ))
                }
            }
            .onDelete { draft.prices?.remove(atOffsets: $0) }
            Button("Add price", systemImage: "plus") {
                draft.prices = (draft.prices ?? []) + [ParkPrice(name: "", price: "")]
            }
        }
    }

    private var linksSection: some View {
        Section("Links") {
            ForEach((draft.links ?? []).indices, id: \.self) { index in
                VStack(alignment: .leading) {
                    TextField("Kind (booking, instagram…)", text: Binding(
                        get: { draft.links?[index].kind ?? "" },
                        set: { draft.links?[index].kind = $0 }
                    ))
                    .textInputAutocapitalization(.never)
                    TextField("URL", text: Binding(
                        get: { draft.links?[index].url ?? "" },
                        set: { draft.links?[index].url = $0 }
                    ))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
            }
            .onDelete { draft.links?.remove(atOffsets: $0) }
            Button("Add link", systemImage: "plus") {
                draft.links = (draft.links ?? []) + [ParkLink(kind: "", url: "")]
            }
        }
    }

    // MARK: Helpers

    private struct TraceTarget: Identifiable { let index: Int; var id: Int { index } }

    private func save() {
        var park = draft
        park.name = park.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if park.id.isEmpty { park.id = ParkStore.shared.newParkID(for: park.name) }
        park.cables = park.cables?.map { cable in
            var cable = cable
            if cable.name?.isEmpty == true { cable.name = nil }
            return cable
        }
        do {
            try ParkStore.shared.save(park)
            onSaved()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func issueText(_ issue: ParkDraft.Issue) -> String {
        switch issue {
        case .missingName: String(localized: "Name is required.")
        case .invalidLocation: String(localized: "Set the park location.")
        case .cableTooShort(let index): String(localized: "Cable \(index + 1) needs at least 2 points (or none).")
        case .invalidCablePoint(let index): String(localized: "Cable \(index + 1) has an invalid point.")
        }
    }

    private func text(_ binding: Binding<String?>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }

    private func cableField<T>(_ index: Int, _ keyPath: WritableKeyPath<ParkCable, T>) -> Binding<T> {
        Binding(
            get: { draft.cables![index][keyPath: keyPath] },
            set: { draft.cables![index][keyPath: keyPath] = $0 }
        )
    }

    private func cableBinding(_ index: Int) -> Binding<ParkCable> {
        Binding(
            get: { draft.cables?.indices.contains(index) == true ? draft.cables![index] : ParkCable() },
            set: { if draft.cables?.indices.contains(index) == true { draft.cables![index] = $0 } }
        )
    }

    private func priceBinding(_ index: Int, _ keyPath: WritableKeyPath<ParkPrice, String>) -> Binding<String> {
        Binding(
            get: { draft.prices?[index][keyPath: keyPath] ?? "" },
            set: { draft.prices?[index][keyPath: keyPath] = $0 }
        )
    }

    private func updateOpening(_ change: (inout ParkOpening) -> Void) {
        var opening = draft.opening ?? ParkOpening()
        change(&opening)
        draft.opening = opening
    }

    private func coordinateField(_ title: LocalizedStringKey, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...6)))
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 160)
        }
    }
}

// MARK: - Reusable editors

private struct StringListEditor: View {
    let title: LocalizedStringKey
    let addLabel: LocalizedStringKey
    @Binding var items: [String]

    var body: some View {
        ForEach(items.indices, id: \.self) { index in
            TextField(title, text: $items[index])
        }
        .onDelete { items.remove(atOffsets: $0) }
        Button(addLabel, systemImage: "plus") { items.append("") }
    }
}

/// `HH:mm` string as a native time picker.
private struct TimeField: View {
    let title: LocalizedStringKey
    @Binding var value: String

    var body: some View {
        DatePicker(title, selection: Binding(get: parse, set: format), displayedComponents: .hourAndMinute)
    }

    private func parse() -> Date {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        let calendar = Calendar.current
        return calendar.date(
            bySettingHour: parts.first ?? 9, minute: parts.count > 1 ? parts[1] : 0, second: 0, of: Date()
        ) ?? Date()
    }

    private func format(_ date: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        value = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

/// Months / days / from / until / dates shared by opening rules and blocks.
private struct SelectorFields: View {
    @Binding var months: [Int]?
    @Binding var days: [String]?
    @Binding var from: String?
    @Binding var until: String?
    @Binding var dates: [String]?

    private static let dayTokens = ["mon", "tue", "wed", "thu", "fri", "sat", "sun", "weekdays", "weekend", "daily"]

    var body: some View {
        Menu {
            ForEach(1...12, id: \.self) { month in
                Toggle(Calendar.current.monthSymbols[month - 1], isOn: toggle($months, month))
            }
        } label: {
            LabeledContent("Months", value: months.map { $0.sorted().map(String.init).joined(separator: ",") } ?? String(localized: "All"))
        }
        Menu {
            ForEach(Self.dayTokens, id: \.self) { token in
                Toggle(token, isOn: toggle($days, token))
            }
        } label: {
            LabeledContent("Days", value: days?.joined(separator: ",") ?? String(localized: "All"))
        }
        optionalDate("From", $from)
        optionalDate("Until", $until)
        ForEach((dates ?? []).indices, id: \.self) { index in
            DatePicker("Date", selection: Binding(
                get: { Self.parse(dates?[index]) ?? Date() },
                set: { dates?[index] = Self.format($0) }
            ), displayedComponents: .date)
        }
        .onDelete { dates?.remove(atOffsets: $0); if dates?.isEmpty == true { dates = nil } }
        Button("Add special date", systemImage: "calendar.badge.plus") {
            dates = (dates ?? []) + [Self.format(Date())]
        }
    }

    private func optionalDate(_ title: LocalizedStringKey, _ binding: Binding<String?>) -> some View {
        HStack {
            Toggle(title, isOn: Binding(
                get: { binding.wrappedValue != nil },
                set: { binding.wrappedValue = $0 ? Self.format(Date()) : nil }
            ))
            if let value = binding.wrappedValue {
                DatePicker("", selection: Binding(
                    get: { Self.parse(value) ?? Date() },
                    set: { binding.wrappedValue = Self.format($0) }
                ), displayedComponents: .date)
                .labelsHidden()
            }
        }
    }

    private func toggle<T: Hashable>(_ binding: Binding<[T]?>, _ value: T) -> Binding<Bool> {
        Binding(
            get: { binding.wrappedValue?.contains(value) ?? false },
            set: { on in
                var items = binding.wrappedValue ?? []
                if on { items.append(value) } else { items.removeAll { $0 == value } }
                binding.wrappedValue = items.isEmpty ? nil : items
            }
        )
    }

    private static func parse(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)
    }

    private static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private struct RuleEditor: View {
    @Binding var rule: ParkOpeningRule

    var body: some View {
        DisclosureGroup {
            TextField("Label", text: Binding(
                get: { rule.label ?? "" },
                set: { rule.label = $0.isEmpty ? nil : $0 }
            ))
            TimeField(title: "Opens", value: $rule.open)
            TimeField(title: "Closes", value: $rule.close)
            SelectorFields(months: $rule.months, days: $rule.days, from: $rule.from, until: $rule.until, dates: $rule.dates)
            TextField("Note", text: Binding(
                get: { rule.note ?? "" },
                set: { rule.note = $0.isEmpty ? nil : $0 }
            ))
        } label: {
            Text(rule.label ?? "\(rule.open)–\(rule.close)")
        }
    }
}

private struct SlotEditor: View {
    @Binding var slot: ParkSlot

    var body: some View {
        DisclosureGroup {
            TextField("Block id", text: $slot.id)
            TextField("Label", text: Binding(
                get: { slot.label ?? "" },
                set: { slot.label = $0.isEmpty ? nil : $0 }
            ))
            TimeField(title: "Start", value: $slot.start)
            TimeField(title: "End", value: $slot.end)
            SelectorFields(months: $slot.months, days: $slot.days, from: $slot.from, until: $slot.until, dates: $slot.dates)
        } label: {
            Text("Block \(slot.id) · \(slot.start)–\(slot.end)")
        }
    }
}

// MARK: - Location picker

private struct LocationPickerView: View {
    @Binding var coordinate: ParkCoordinate
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettingsKey.mapUsesSatellite) private var usesSatellite = false
    @State private var picked: CLLocationCoordinate2D?

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(initialPosition: initialPosition) {
                    if let picked { Marker("", coordinate: picked).tint(.red) }
                }
                .mapStyle(usesSatellite ? .hybrid : .standard)
                .onTapGesture { screen in picked = proxy.convert(screen, from: .local) }
            }
            .navigationTitle("Pick location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        if let picked { coordinate = ParkCoordinate(lat: picked.latitude, lon: picked.longitude) }
                        dismiss()
                    }
                    .disabled(picked == nil)
                }
            }
        }
    }

    private var initialPosition: MapCameraPosition {
        guard ParkDraft.isValid(coordinate) else { return .automatic }
        return .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: coordinate.lat, longitude: coordinate.lon),
            latitudinalMeters: 1500,
            longitudinalMeters: 1500
        ))
    }
}
