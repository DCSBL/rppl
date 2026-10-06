import MapKit
import RpplCore
import SwiftUI

// MARK: - Text

/// A text field for park text. What is typed or pasted is cleaned as it comes in (no control
/// characters, no bidi tricks) and cut at the field's length limit; any script and emoji stay.
struct ParkTextInput: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let field: ParkTextField
    var axis: Axis = .horizontal
    var lines: ClosedRange<Int> = 1...1

    var body: some View {
        TextField(title, text: $text, axis: axis)
            .lineLimit(axis == .vertical ? lines : 1...1)
            .onChange(of: text) { _, new in
                let clean = ParkText.sanitizeTyping(new, field: field)
                if clean != new { text = clean }
            }
    }
}

/// Footer text under a group of fields: what is asked for, a friendly hint when a value does not look
/// right yet, and a character count once the limit comes near.
struct ParkFieldHelp: View {
    let text: LocalizedStringKey
    var problem: LocalizedStringKey?
    var counter: (count: Int, limit: Int)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
            }
            Text(text)
            if let counter, counter.count * 4 >= counter.limit * 3 {
                Text(verbatim: "\(counter.count) / \(counter.limit)")
                    .monospacedDigit()
                    .foregroundStyle(counter.count >= counter.limit ? .orange : .secondary)
            }
        }
    }
}

extension Binding where Value == String? {
    /// An optional string as a plain one: nil reads as empty, empty is stored as nil.
    var orEmpty: Binding<String> {
        Binding<String>(
            get: { wrappedValue ?? "" },
            set: { wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}

// MARK: - Lists that grow and shrink by themselves

/// Remembers one id per row, so a row keeps its identity (and its keyboard focus) while its content
/// changes. Plain class on purpose: it is bookkeeping, not state that should redraw the view.
private final class RowIDs {
    var values: [UUID] = []

    func resolve(count: Int) -> [UUID] {
        if values.count > count { values.removeLast(values.count - count) }
        while values.count < count { values.append(UUID()) }
        return values
    }
}

struct GhostRowContext {
    let id: UUID
    /// Position in the list; nil for the empty row at the end.
    let index: Int?
    /// The empty row at the end: it becomes a real row as soon as something is filled in.
    let isGhost: Bool
    let focus: FocusState<UUID?>.Binding
}

/// What a `GhostList` needs to know about its items.
struct GhostListRules<Item> {
    /// A new, empty item (the content of the empty row).
    let blank: () -> Item
    /// Whether an item has nothing in it yet.
    let isBlank: (Item) -> Bool
    /// Title and message of the question asked before a swipe deletes this item. nil deletes at once.
    var confirmDelete: ((Item) -> (title: String, message: String)?)?
}

/// Rows for a list the person fills in: there is always one empty row at the end, and the moment
/// something is typed in it, it becomes a real row and a new empty one appears below. A real row that
/// is left empty when the keyboard goes away is removed; swipe removes the others (asking first when
/// `confirmDelete` says so).
struct GhostList<Item: Equatable, Row: View>: View {
    @Binding var items: [Item]
    let maxCount: Int
    let rules: GhostListRules<Item>
    @ViewBuilder let row: (Binding<Item>, GhostRowContext) -> Row

    @Environment(ParkEditorSession.self) private var session
    @State private var ids = RowIDs()
    @State private var ghost: Item
    @State private var ghostID = UUID()
    @FocusState private var focused: UUID?

    init(
        items: Binding<[Item]>,
        maxCount: Int,
        rules: GhostListRules<Item>,
        @ViewBuilder row: @escaping (Binding<Item>, GhostRowContext) -> Row
    ) {
        _items = items
        self.maxCount = maxCount
        self.rules = rules
        self.row = row
        _ghost = State(initialValue: rules.blank())
    }

    var body: some View {
        let realIDs = ids.resolve(count: items.count)
        let rowIDs = items.count < maxCount ? realIDs + [ghostID] : realIDs
        ForEach(rowIDs, id: \.self) { id in
            let isGhost = id == ghostID
            row(binding(for: id), GhostRowContext(id: id, index: isGhost ? nil : index(of: id), isGhost: isGhost, focus: $focused))
                .onChange(of: focused) { old, new in
                    if old == id, new != id { removeIfBlank(id) }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !isGhost {
                        Button(role: .destructive) { requestDelete(id) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
        }
    }

    private func index(of id: UUID) -> Int? {
        ids.values.firstIndex(of: id).flatMap { items.indices.contains($0) ? $0 : nil }
    }

    /// Decides what it is writing to when it writes, not when it was made: a keystroke that lands on a
    /// row just after it turned from the empty row into a real one must update that row, not add another.
    private func binding(for id: UUID) -> Binding<Item> {
        Binding(
            get: {
                if id == ghostID { return ghost }
                return index(of: id).map { items[$0] } ?? rules.blank()
            },
            set: { new in
                if id == ghostID {
                    guard !rules.isBlank(new) else { ghost = new; return }
                    ids.values = ids.resolve(count: items.count) + [id]
                    items.append(new)
                    ghost = rules.blank()
                    ghostID = UUID()
                } else if let index = index(of: id) {
                    items[index] = new
                }
            }
        )
    }

    private func removeIfBlank(_ id: UUID) {
        guard let index = index(of: id), rules.isBlank(items[index]) else { return }
        withAnimation {
            ids.values.remove(at: index)
            items.remove(at: index)
        }
    }

    private func requestDelete(_ id: UUID) {
        guard let index = index(of: id) else { return }
        let item = items[index]
        guard let question = rules.confirmDelete?(item) else {
            delete(id)
            return
        }
        session.askToDelete(title: question.title, message: question.message) { delete(id) }
    }

    private func delete(_ id: UUID) {
        guard let index = index(of: id) else { return }
        withAnimation {
            ids.values.remove(at: index)
            items.remove(at: index)
        }
    }
}

/// The empty row of a list whose items have no text to type (hours, blocks, dates): looks like an
/// empty row and fills itself in with a first, editable item when touched.
struct GhostPlaceholderRow: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.rpplAccent)
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Time and date

private let utcZone = TimeZone(secondsFromGMT: 0) ?? .gmt

private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utcZone
    return calendar
}

/// A `HH:mm` string (24 hour, as stored) behind the system time picker, which shows the device's own
/// 12 or 24 hour style. Works in UTC so a daylight saving day can never shift the time.
struct ParkTimePicker: View {
    let title: LocalizedStringKey
    @Binding var time: String

    var body: some View {
        DatePicker(title, selection: date, displayedComponents: .hourAndMinute)
            .environment(\.calendar, utcCalendar)
            .environment(\.timeZone, utcZone)
    }

    private var date: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSinceReferenceDate: TimeInterval((ParkSchedule.minutes(time) ?? 540) % 1440 * 60)) },
            set: { newValue in
                let minutes = Int((newValue.timeIntervalSinceReferenceDate / 60).rounded(.down))
                time = ParkClock.text(minutes: minutes)
            }
        )
    }
}

/// A `yyyy-MM-dd` string behind the system date picker; the day never shifts with the time zone.
struct ParkDatePicker: View {
    let title: LocalizedStringKey
    @Binding var iso: String

    var body: some View {
        DatePicker(title, selection: date, displayedComponents: .date)
            .environment(\.calendar, utcCalendar)
            .environment(\.timeZone, utcZone)
    }

    private var date: Binding<Date> {
        Binding(
            get: { ParkDateText.date(from: iso) ?? Date() },
            set: { iso = ParkDateText.iso(from: $0) }
        )
    }
}

enum ParkEditorDates {
    /// Today as `yyyy-MM-dd`, in the device's calendar day.
    static var todayISO: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    static func shortDate(_ iso: String) -> String {
        guard let date = ParkDateText.date(from: iso) else { return iso }
        return date.formatted(Date.FormatStyle(timeZone: utcZone).day().month(.abbreviated).year())
    }
}

// MARK: - Choosing from a list

/// A page of rows you switch on and off, with quick picks above. Replaces menus of toggles.
struct ParkToggleListPage<Value: Hashable>: View {
    let title: LocalizedStringKey
    let footer: LocalizedStringKey
    let options: [(value: Value, label: String)]
    @Binding var selection: Set<Value>
    var shortcuts: [(label: String, values: Set<Value>)] = []

    var body: some View {
        Form {
            if !shortcuts.isEmpty {
                Section {
                    ForEach(shortcuts.indices, id: \.self) { index in
                        Button(shortcuts[index].label) { selection = shortcuts[index].values }
                    }
                }
            }
            Section {
                ForEach(options, id: \.value) { option in
                    Button {
                        if selection.contains(option.value) {
                            selection.remove(option.value)
                        } else {
                            selection.insert(option.value)
                        }
                    } label: {
                        HStack {
                            Text(option.label).foregroundStyle(.primary)
                            Spacer()
                            if selection.contains(option.value) {
                                Image(systemName: "checkmark").foregroundStyle(Color.rpplAccent)
                            }
                        }
                    }
                }
            } footer: {
                Text(footer)
            }
        }
        .dismissKeyboardOnTapOutside()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Maps

/// The crosshair of the "move the map, then set" pickers.
struct MapCrosshair: View {
    var body: some View {
        ZStack {
            Circle().strokeBorder(.white, lineWidth: 2).frame(width: 26, height: 26)
            Circle().fill(Color.rpplAccent).frame(width: 8, height: 8)
        }
        .shadow(color: .black.opacity(0.5), radius: 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Small map that only shows: the park pin and, when given, a traced cable.
struct ParkMiniMap: View {
    let coordinate: ParkCoordinate
    var cable: ParkCable?
    var meters: Double = 600
    var height: CGFloat = 150

    @AppStorage(AppSettingsKey.mapUsesSatellite) private var usesSatellite = false

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: []) {
            if let cable {
                let line = (cable.points ?? []).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                if line.count >= 2 {
                    MapPolyline(coordinates: cable.direction?.isLoop == true ? line + [line[0]] : line)
                        .stroke(Color.rpplAccent, lineWidth: 3)
                }
            } else {
                Marker("", coordinate: CLLocationCoordinate2D(latitude: coordinate.lat, longitude: coordinate.lon))
                    .tint(.red)
            }
        }
        .mapStyle(usesSatellite ? .hybrid : .standard)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .allowsHitTesting(false)
        .id("\(coordinate.lat),\(coordinate.lon),\(cable?.points?.count ?? 0)")
    }

    private var region: MKCoordinateRegion {
        var points = [coordinate]
        if let traced = cable?.points, traced.count >= 2 { points = traced.map(\.coordinate) }
        let lats = points.map(\.lat)
        let lons = points.map(\.lon)
        let center = CLLocationCoordinate2D(
            latitude: ((lats.min() ?? coordinate.lat) + (lats.max() ?? coordinate.lat)) / 2,
            longitude: ((lons.min() ?? coordinate.lon) + (lons.max() ?? coordinate.lon)) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(((lats.max() ?? 0) - (lats.min() ?? 0)) * 1.6, meters / 111_000),
            longitudeDelta: max(((lons.max() ?? 0) - (lons.min() ?? 0)) * 1.6, meters / 111_000)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

// MARK: - Keyboard

extension View {
    /// Tapping anywhere outside a text field closes the keyboard; dragging the page does too. Applied
    /// per page: a modifier on the navigation stack does not reach every pushed page.
    func dismissKeyboardOnTapOutside() -> some View {
        scrollDismissesKeyboard(.interactively)
            .background(KeyboardTapDismisser())
    }
}

/// Adds a tap recognizer to the window that resigns first responder, unless the tap lands in a text
/// input. It never cancels the touch, so buttons and rows keep working.
private struct KeyboardTapDismisser: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var window: UIWindow?
        private lazy var recognizer: UITapGestureRecognizer = {
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            return tap
        }()

        func attach(to window: UIWindow?) {
            guard let window, self.window !== window else { return }
            detach()
            window.addGestureRecognizer(recognizer)
            self.window = window
        }

        func detach() {
            window?.removeGestureRecognizer(recognizer)
            window = nil
        }

        @objc private func tapped() {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            !(touch.view?.isInsideTextInput ?? false)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}

private extension UIView {
    var isInsideTextInput: Bool {
        var view: UIView? = self
        while let current = view {
            if current is UITextField || current is UITextView { return true }
            view = current.superview
        }
        return false
    }
}
