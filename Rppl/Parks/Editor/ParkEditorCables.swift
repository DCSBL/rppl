import RpplCore
import SwiftUI

struct ParkCablesPage: View {
    @Environment(ParkEditorSession.self) private var session

    var body: some View {
        Form {
            ParkPageIntro(
                page: .cables,
                text: "Add every cable the park has. Trace it on the satellite map if the imagery is clear enough; a cable without a trace is fine too."
            )
            Section {
                GhostList(
                    items: cables,
                    maxCount: ParkLimits.cables,
                    rules: GhostListRules(
                        blank: { ParkCable() },
                        isBlank: { $0 == ParkCable() },
                        confirmDelete: { cable in
                            let name = cable.name ?? String(localized: "this cable")
                            let traced = (cable.points ?? []).isEmpty
                                ? ""
                                : " " + String(localized: "Its traced points go with it.")
                            return (
                                String(localized: "Delete \(name)?"),
                                String(localized: "This cannot be undone.") + traced
                            )
                        }
                    )
                ) { cable, context in
                    ParkCableRow(cable: cable, context: context)
                }
            } header: {
                Text("Cables")
            } footer: {
                Text("Type a name to add a cable, for example Beginner or Main cable. Tap the line under a name for its details and the trace.")
            }
        }
        .dismissKeyboardOnTapOutside()
        .navigationTitle("Cables")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var cables: Binding<[ParkCable]> {
        Binding(
            get: { session.park.cables ?? [] },
            set: { session.park.cables = $0.isEmpty ? nil : $0 }
        )
    }
}

private struct ParkCableRow: View {
    @Binding var cable: ParkCable
    let context: GhostRowContext
    @Environment(ParkEditorSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ParkTextInput(
                title: context.isGhost ? "Add a cable" : "Name (optional)",
                text: $cable.name.orEmpty,
                field: .label
            )
            .textInputAutocapitalization(.sentences)
            .focused(context.focus, equals: context.id)
            if let index = context.index {
                Button {
                    session.path.append(.cable(index))
                } label: {
                    HStack {
                        Text(ParkFormatting.cableSummary(cable))
                            .font(.footnote)
                            .foregroundStyle(cable.points == nil ? Color.rpplAccent : .secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

// MARK: - One cable

struct ParkCableDetailPage: View {
    let index: Int
    @Environment(ParkEditorSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var location = ParksLocationProvider()
    @State private var tracing = false
    /// Set once deletion is confirmed; the cable is removed after this page is gone (see `onDisappear`).
    @State private var deleting = false

    private enum Kind: Hashable { case fullSize, twoPointZero }

    var body: some View {
        if let cable = session.park.cables?[safe: index] {
            Form {
                Section {
                    ParkTextInput(title: "Name (optional)", text: field(\.name).orEmpty, field: .label)
                } header: {
                    Text("Name")
                } footer: {
                    Text("What riders call this cable: Beginner, Main cable, Cable 2.")
                }

                Section {
                    Picker("Type", selection: kind) {
                        Text("Full size").tag(Kind?.some(.fullSize))
                        Text("2.0").tag(Kind?.some(.twoPointZero))
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    // The traced order already tells the direction; only ask without a trace.
                    if cable.direction?.isLoop == true, (cable.points ?? []).count < 3 {
                        Picker("Direction", selection: loopDirection) {
                            Text("Clockwise").tag(ParkCableDirection.clockwise)
                            Text("Counter-clockwise").tag(ParkCableDirection.counterClockwise)
                        }
                    }
                } header: {
                    Text("Type")
                } footer: {
                    Text("Full size goes round the lake past every corner. A 2.0 cable runs back and forth between two towers. The direction follows the order you trace the points in.")
                }

                Section {
                    if (cable.points ?? []).count >= 2 {
                        ParkMiniMap(coordinate: cable.points?.first?.coordinate ?? session.park.location, cable: cable, height: 180)
                            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                        LabeledContent("Traced", value: ParkFormatting.cableSummary(cable))
                    }
                    Button(
                        (cable.points ?? []).isEmpty ? "Trace on the map" : "Edit the trace",
                        systemImage: "scribble.variable"
                    ) { tracing = true }
                } header: {
                    Text("Trace")
                } footer: {
                    Text("Tap points along the cable, in the direction riders travel. The first point is the start; you can flag more starts.")
                }

                Section {
                    TextField("Length in metres", value: field(\.lengthM), format: .number)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Length")
                } footer: {
                    Text(lengthFooter(cable))
                }

                Section {
                    ParkTextInput(
                        title: "What riders should know",
                        text: field(\.description).orEmpty,
                        field: .cableDescription,
                        axis: .vertical,
                        lines: 2...8
                    )
                } header: {
                    Text("Description")
                } footer: {
                    ParkFieldHelp(
                        text: "Optional. Short and factual: who it suits and what is on it.",
                        counter: (cable.description?.count ?? 0, ParkTextField.cableDescription.maxLength)
                    )
                }

                Section {
                    Button("Delete cable", systemImage: "trash", role: .destructive) {
                        let name = cable.name ?? String(localized: "this cable")
                        session.askToDelete(
                            title: String(localized: "Delete \(name)?"),
                            message: String(localized: "This cannot be undone.")
                        ) {
                            deleting = true
                            session.path.removeLast()
                        }
                    }
                }
            }
            .dismissKeyboardOnTapOutside()
            .navigationTitle(cable.name ?? String(localized: "Cable \(index + 1)"))
            .navigationBarTitleDisplayMode(.inline)
            .task { location.refresh() }
            .onDisappear {
                guard deleting else { return }
                session.park.cables?.remove(at: index)
                if session.park.cables?.isEmpty == true { session.park.cables = nil }
            }
            .fullScreenCover(isPresented: $tracing) {
                CableTraceView(cable: cableBinding, center: traceCenter)
            }
        }
    }

    private func lengthFooter(_ cable: ParkCable) -> String {
        if let computed = cable.computedLengthM, cable.lengthM == nil {
            return String(localized: "Optional. Left empty, the length of the trace is used: \(DistanceFormat.meters(computed)).")
        }
        return String(localized: "Optional. Fill it in when the park publishes the length; it wins over the trace.")
    }

    private var cableBinding: Binding<ParkCable> {
        Binding(
            get: { session.park.cables?[safe: index] ?? ParkCable() },
            set: { new in
                if session.park.cables?.indices.contains(index) == true { session.park.cables?[index] = new }
            }
        )
    }

    private func field<T>(_ keyPath: WritableKeyPath<ParkCable, T>) -> Binding<T> {
        Binding(
            get: { (session.park.cables?[safe: index] ?? ParkCable())[keyPath: keyPath] },
            set: { new in
                if session.park.cables?.indices.contains(index) == true { session.park.cables?[index][keyPath: keyPath] = new }
            }
        )
    }

    private var kind: Binding<Kind?> {
        Binding(
            get: {
                guard let direction = session.park.cables?[safe: index]?.direction else { return nil }
                if direction.isLoop { return .fullSize }
                return direction == .twoPointZero ? .twoPointZero : nil
            },
            set: { new in
                guard session.park.cables?.indices.contains(index) == true else { return }
                switch new {
                case .fullSize?:
                    guard session.park.cables?[index].direction?.isLoop != true else { return }
                    // The traced order tells which way riders go; without a trace, clockwise.
                    let clockwise = session.park.cables?[index].tracedWindingIsClockwise ?? true
                    session.park.cables?[index].direction = clockwise ? .clockwise : .counterClockwise
                case .twoPointZero?: session.park.cables?[index].direction = .twoPointZero
                case nil: session.park.cables?[index].direction = nil
                }
            }
        )
    }

    private var loopDirection: Binding<ParkCableDirection> {
        Binding(
            get: { session.park.cables?[safe: index]?.direction ?? .clockwise },
            set: { new in
                if session.park.cables?.indices.contains(index) == true { session.park.cables?[index].direction = new }
            }
        )
    }

    /// Where the trace map opens: the first traced point, the park pin, any other cable, else the user.
    private var traceCenter: ParkCoordinate {
        if ParkDraft.isValid(session.park.location) { return session.park.location }
        if let centroid = ParkDraft.centroid(of: session.park.cables ?? []) { return centroid }
        return location.coordinate ?? ParkCoordinate(lat: 52.1, lon: 5.3)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
