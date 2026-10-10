import RpplCore
import SwiftUI
import UIKit

/// What the editor changes; `isDirty` is `draft != initial`, like the park editor.
struct ManualSessionDraft: Equatable, Sendable {
    var start: Date
    var end: Date
    var parkId: String?
    /// Own location, when no park is picked.
    var spot: ParkCoordinate?
    var spotName: String?
    var tallies: [ManualEntry.Tally]

    /// A two-hour session that ended now (to the minute).
    static func new(now: Date = .now) -> ManualSessionDraft {
        let end = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60)
        return ManualSessionDraft(
            start: end.addingTimeInterval(-7_200), end: end, tallies: [ManualEntry.Tally()]
        )
    }

    /// One tally per cable of the picked park (one otherwise); kept values stay at their index.
    mutating func fitTallies(to parks: [Park]) {
        let cables = max(1, parks.first { $0.id == parkId }?.cables?.count ?? 1)
        tallies = (0..<cables).map { tallies.indices.contains($0) ? tallies[$0] : ManualEntry.Tally() }
    }

    mutating func setPlace(parkId: String?, spot: ParkCoordinate?, name: String?, parks: [Park]) {
        self.parkId = parkId
        self.spot = spot
        spotName = name
        fitTallies(to: parks)
    }
}

/// Add a past session by hand, or edit one. Hand-entered sessions never touch HealthKit.
struct ManualSessionEditorView: View {
    var editing: String?
    var onSaved: (String) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var connectivity = PhoneConnectivityService.shared
    @State private var parks: [Park]
    @State private var draft: ManualSessionDraft
    @State private var initial: ManualSessionDraft
    @State private var isSaving = false
    @State private var showDiscard = false
    @State private var errorText: String?
    @State private var showReversed = false
    @State private var showLong = false
    /// The other picker follows the first day change only; after that both are free.
    @State private var didAlignDay = false

    init(editing sessionId: String? = nil, onSaved: @escaping (String) -> Void = { _ in }) {
        editing = sessionId
        self.onSaved = onSaved
        let parks = ParkCatalog.load(userRoot: AppConstants.localPhoneParksRoot)
        var loaded = sessionId.flatMap { Self.load($0) } ?? .new()
        loaded.fitTallies(to: parks)
        _parks = State(initialValue: parks)
        _draft = State(initialValue: loaded)
        _initial = State(initialValue: loaded)
    }

    private static func load(_ sessionId: String) -> ManualSessionDraft? {
        let store = PhoneConnectivityService.shared.store
        guard let manifest = try? store.readManifest(sessionId: sessionId), let manual = manifest.manual else {
            return nil
        }
        let ownSpot = manifest.parkId == nil
        return ManualSessionDraft(
            start: manifest.startedAt,
            end: manifest.endedAt ?? manifest.startedAt,
            parkId: manifest.parkId,
            spot: ownSpot ? manual.location : nil,
            spotName: ownSpot ? (try? store.readDerivedView(sessionId: sessionId))?.cityName : nil,
            tallies: manual.tallies
        )
    }

    private var isDirty: Bool { draft != initial }
    private var isReversed: Bool { ManualTimeRange.isReversed(start: draft.start, end: draft.end) }
    private var longDuration: String {
        let seconds = max(0, draft.end.timeIntervalSince(draft.start))
        let whole = Duration.seconds(Int(seconds / 3_600) * 3_600)
        return whole.formatted(.units(allowed: [.days, .hours], width: .wide, zeroValueUnits: .hide))
    }
    private var park: Park? { parks.first { $0.id == draft.parkId } }
    private var cables: [ParkCable] { park?.cables ?? [] }
    private var distanceM: Double? { ManualEntry.distanceM(tallies: draft.tallies, cables: cables) }

    private var locationText: String {
        if let park { return park.name }
        if draft.spot != nil { return draft.spotName ?? String(localized: "Own location") }
        return String(localized: "No location")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Location") {
                    NavigationLink {
                        ManualSessionLocationPicker(parks: parks, draft: $draft)
                    } label: {
                        LabeledContent("Location", value: locationText)
                    }
                }
                Section("Time") {
                    DatePicker("Start", selection: $draft.start, in: ...Date.now)
                        .foregroundStyle(isReversed ? Color.red : Color.primary)
                        .tint(isReversed ? .red : nil)
                    DatePicker("End", selection: $draft.end, in: ...Date.now)
                        .foregroundStyle(isReversed ? Color.red : Color.primary)
                        .tint(isReversed ? .red : nil)
                    Button("Today", action: resetToToday)
                }
                if cables.count > 1 {
                    ForEach(cables.indices, id: \.self) { index in
                        Section(cables[index].name ?? String(localized: "Cable \(index + 1)")) {
                            tallyRows($draft.tallies[index])
                        }
                    }
                } else {
                    Section("Sets & laps") { tallyRows($draft.tallies[0]) }
                }
                if let distanceM {
                    Section {
                        LabeledContent("Estimated distance", value: LogbookFormatting.approximateDistance(distanceM))
                    } footer: {
                        Text("Laps times the cable length.")
                    }
                }
            }
            .navigationTitle(editing == nil ? "New session" : "Edit session")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isDirty)
            .onChange(of: draft.start) { old, new in
                if let moved = alignedDay(old: old, new: new, other: draft.end) { draft.end = moved }
            }
            .onChange(of: draft.end) { old, new in
                if let moved = alignedDay(old: old, new: new, other: draft.start) { draft.start = moved }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty { showDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveTapped).disabled(isSaving || (editing != nil && !isDirty))
                }
            }
            .confirmationDialog("Discard changes?", isPresented: $showDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .alert("End is before start", isPresented: $showReversed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Set an end time after the start time to save this session.")
            }
            .alert("Save long session?", isPresented: $showLong) {
                Button("Save", action: save)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to save a session of \(longDuration)?")
            }
            .alert("Could not save session", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    @ViewBuilder
    private func tallyRows(_ tally: Binding<ManualEntry.Tally>) -> some View {
        CountField(title: "Sets", value: tally.sets)
        CountField(title: "Laps", value: tally.laps)
    }

    /// First day change of either picker moves the other onto that day (time kept).
    private func alignedDay(old: Date, new: Date, other: Date) -> Date? {
        guard !didAlignDay, !Calendar.current.isDate(old, inSameDayAs: new) else { return nil }
        didAlignDay = true
        return ManualTimeRange.moved(other, toDayOf: new, now: .now)
    }

    private func resetToToday() {
        // Both land on today already; the one-shot alignment has nothing left to do.
        didAlignDay = true
        let now = Date.now
        draft.start = ManualTimeRange.moved(draft.start, toDayOf: now, now: now)
        draft.end = ManualTimeRange.moved(draft.end, toDayOf: now, now: now)
    }

    private func saveTapped() {
        if isReversed {
            showReversed = true
        } else if ManualTimeRange.isLong(start: draft.start, end: draft.end) {
            showLong = true
        } else {
            save()
        }
    }

    private func save() {
        isSaving = true
        let store = connectivity.store
        let (draft, editing) = (draft, editing)
        let entry = ManualEntry(tallies: draft.tallies, distanceM: distanceM, location: park?.location ?? draft.spot)
        let parkId = park?.id
        let label = park?.name ?? (draft.spot == nil ? nil : (draft.spotName ?? String(localized: "Own location")))
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let system = UIDevice.current.systemVersion
        Task {
            do {
                let (sessionId, weatherChanged) = try await StoreIO.runOffMain { () -> (String, Bool) in
                    let existing = editing.flatMap { try? store.readManifest(sessionId: $0) }
                    var manifest = existing ?? SessionManifest(
                        testerId: TesterIdentity.resolve(),
                        appVersion: version,
                        buildNumber: build,
                        watchModel: "none",
                        systemVersion: system,
                        transferState: .acknowledged,
                        activityCode: ActivityCodes.wakeboard
                    )
                    let changed = existing == nil || manifest.startedAt != draft.start
                        || manifest.endedAt != draft.end || manifest.manual?.location != entry.location
                    manifest.startedAt = draft.start
                    manifest.endedAt = draft.end
                    manifest.parkId = parkId
                    manifest.parkIdSource = SessionParkSource.manual
                    manifest.manual = entry
                    manifest.setFlags = manifest.setFlags.map { SetFlags.trimmed($0, toSetCount: entry.setCount ?? 0) }
                    if changed { manifest.weather = nil }
                    if changed || existing?.parkId != parkId { manifest.waterTemperatureEstimate = nil }
                    try store.saveManual(manifest, label: label)
                    return (manifest.sessionId, changed)
                }
                PhoneICloudDriveController.shared.acceptSession(sessionId)
                connectivity.bumpSessionsRevision()
                onSaved(sessionId)
                dismiss()
                if weatherChanged, let spot = entry.location {
                    Task {
                        await ManualSessionWeather.refresh(
                            store: store, sessionId: sessionId, at: spot, from: draft.start, to: draft.end
                        )
                    }
                }
            } catch {
                isSaving = false
                errorText = error.localizedDescription
                WakeLog.error(.store, "manual session save: \(error.localizedDescription)")
            }
        }
    }
}

/// A count with + / - buttons and a number you can type.
private struct CountField: View {
    let title: LocalizedStringKey
    @Binding var value: Int?

    /// "-" (nil, no data) sits one step below 0: -, 0, 1, 2, ...
    private var stepperValue: Binding<Int> {
        Binding(
            get: { value ?? -1 },
            set: { value = $0 < 0 ? nil : min($0, 999) }
        )
    }

    var body: some View {
        Stepper(value: stepperValue, in: -1...999) {
            HStack {
                Text(title)
                Spacer()
                TextField("-", value: $value, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
            }
        }
        .onChange(of: value) { _, new in
            if let new, new < 0 || new > 999 { value = min(max(new, 0), 999) }
        }
    }
}
