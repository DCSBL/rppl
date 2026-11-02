import CableTracerCore
import RpplCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

public struct ContentView: View {
    @Bindable var model: EditorModel

    public init(model: EditorModel) { self.model = model }

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            HStack(spacing: 0) {
                MapEditorView(model: model)
                Divider()
                InspectorView(model: model)
                    .frame(width: 340)
            }
        }
        .toolbar { toolbar }
        .navigationTitle(model.draft?.name ?? "Cable Tracer")
        #if os(macOS)
        .navigationSubtitle(model.statusMessage)
        #endif
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            Toggle("Only parks without a traced cable", isOn: $model.onlyUntraced)
                .padding(8)
            #if !os(macOS)
            Text(model.statusMessage).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8).lineLimit(2)
            #endif
            List(model.filteredParks, selection: $model.selectedParkID) { park in
                HStack {
                    VStack(alignment: .leading) {
                        Text(park.name)
                        Text(park.id).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    cableBadge(park)
                }
                .tag(park.id)
            }
            .searchable(text: $model.searchText, prompt: "Park")
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
    }

    private func cableBadge(_ park: Park) -> some View {
        let cables = park.cables ?? []
        let traced = cables.filter { ($0.points?.count ?? 0) >= 2 }.count
        return Text(cables.isEmpty ? "–" : "\(traced)/\(cables.count)")
            .font(.caption.monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(traced == cables.count && !cables.isEmpty ? Color.green.opacity(0.25) : Color.orange.opacity(0.25), in: Capsule())
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            #if os(macOS)
            Button { model.chooseDirectory() } label: { Label("Open folder", systemImage: "folder") }
            #endif
            Button { model.reload() } label: { Label("Reload", systemImage: "arrow.clockwise") }
            Button { model.focus() } label: { Label("Fit park", systemImage: "scope") }
                .disabled(model.draft == nil)
            Toggle(isOn: $model.isAddingPoints) { Label("Add points", systemImage: "plus.circle") }
                .disabled(model.selectedCableIndex == nil)
                .help("Click on the map to append a point to the selected cable")
            Menu {
                #if os(macOS)
                Button("Load reference CSV (towers, dock points)…") { loadReferenceCSV() }
                #endif
                Button("Export training set…") { model.exportTrainingSet() }
                    .disabled(model.isExporting)
            } label: { Label("More", systemImage: "ellipsis.circle") }
            Button { model.save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                .disabled(!model.isDirty)
        }
    }

    #if os(macOS)
    private func loadReferenceCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            do { try model.reference.load(csv: url) } catch { model.statusMessage = "Could not read \(url.lastPathComponent)" }
        }
        model.focus()
    }
    #endif
}

/// Right-hand panel: the selected park's cables, their points and the plausibility findings.
struct InspectorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        if let draft = model.draft {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(draft)
                    cables(draft)
                    findings
                }
                .padding(12)
            }
        } else {
            ContentUnavailableView("No park selected", systemImage: "map")
        }
    }

    private func header(_ park: Park) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(park.name).font(.headline)
            Text(String(format: "%.6f, %.6f", park.location.lat, park.location.lon)).font(.caption.monospaced())
            if let address = park.address { Text(address).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Add full size") { model.addCable(.loop) }
                Button("Add 2.0") { model.addCable(.straight) }
                if model.isDirty { Button("Discard") { model.discardChanges() } }
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func cables(_ park: Park) -> some View {
        ForEach(Array((park.cables ?? []).enumerated()), id: \.offset) { index, cable in
            cableSection(index: index, cable: cable, park: park)
        }
    }

    private func cableSection(index: Int, cable: ParkCable, park: Park) -> some View {
        let selected = model.selectedCableIndex == index
        let geometry = CableGeometry(cable: cable, parkLocation: park.location)
        return GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Name", text: Binding(
                    get: { cable.name ?? "" },
                    set: { value in model.updateCable(at: index) { $0.name = value.isEmpty ? nil : value } }
                ))
                Picker("Direction", selection: Binding(
                    get: { cable.direction?.rawValue ?? "" },
                    set: { value in model.updateCable(at: index) { $0.direction = value.isEmpty ? nil : ParkCableDirection(rawValue: value) } }
                )) {
                    Text("–").tag("")
                    Text("ccw").tag("ccw")
                    Text("cw").tag("cw")
                    Text("2.0").tag("2.0")
                }
                TextField("length_m (declared)", value: Binding(
                    get: { cable.lengthM },
                    set: { value in model.updateCable(at: index) { $0.lengthM = value } }
                ), format: .number)
                if geometry.pointsXY.count >= 2 {
                    Text(String(
                        format: "traced %.0f m · box %.0f × %.0f m · heading %.0f° · %.0f m from park",
                        geometry.pathLengthM, geometry.axes.lengthM, geometry.axes.widthM, geometry.axes.headingDegrees, geometry.distanceToParkM
                    ))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                HStack {
                    Button(selected ? "Selected" : "Select") { model.selectedCableIndex = index }.disabled(selected)
                    if (cable.points?.count ?? 0) < 2 {
                        Button("Template") { model.fillTemplate(cableIndex: index) }
                    } else {
                        Button("Reverse") { model.reversePoints(cable: index) }
                        if selected {
                            Button("↺ 5°") { model.rotateSelectedCable(by: -5) }
                            Button("↻ 5°") { model.rotateSelectedCable(by: 5) }
                        }
                    }
                    Spacer()
                    Button(role: .destructive) { model.removeCable(at: index) } label: { Image(systemName: "trash") }
                }
                .controlSize(.small)
                if let points = cable.points, !points.isEmpty {
                    ForEach(Array(points.enumerated()), id: \.offset) { pointIndex, point in
                        HStack(spacing: 6) {
                            Text("\(pointIndex + 1)").frame(width: 18, alignment: .trailing)
                            Text(String(format: "%.5f, %.5f", point.lat, point.lon)).font(.caption.monospaced())
                            Spacer()
                            Toggle("start", isOn: Binding(
                                get: { point.start == true },
                                set: { _ in model.toggleStart(cable: index, point: pointIndex) }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            Button { model.removePoint(cable: index, point: pointIndex) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain)
                        }
                        .font(.caption)
                    }
                } else {
                    Text("Not traced yet").font(.caption).foregroundStyle(.secondary)
                }
            }
        } label: {
            Label(cable.name ?? "Cable \(index + 1)", systemImage: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? Color.accentColor : .primary)
        }
        .onTapGesture { model.selectedCableIndex = index }
    }

    @ViewBuilder
    private var findings: some View {
        let findings = model.findings
        GroupBox("Plausibility") {
            if findings.isEmpty {
                Label("Nothing odd about the traced shapes", systemImage: "checkmark.seal").font(.caption)
            } else {
                ForEach(findings) { finding in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: finding.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(finding.severity == .error ? .red : .orange)
                        VStack(alignment: .leading) {
                            Text(finding.message)
                            Text("cable \(finding.cableIndex + 1)" + (finding.pointIndex.map { ", point \($0 + 1)" } ?? ""))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }
            }
        }
    }
}
