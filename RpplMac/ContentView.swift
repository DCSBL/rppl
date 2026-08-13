import SwiftUI
import RpplCore
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model = SessionAnalysisModel()
    @State private var isImporterPresented = false

    private let thresholds = AssumptionThresholds.default

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolbar
            if let error = model.loadError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            if model.isLoading {
                Text("Loading export…")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.package != nil {
                TimeRangeBar(model: model)
                SessionMapView(locations: model.windowLocations())
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        SpeedChartView(
                            points: model.windowSpeedPoints(),
                            range: model.selectedRange,
                            thresholds: thresholds,
                            highlight: model.visibleHighlight
                        )
                        AccuracyChartView(
                            points: model.windowAccuracyPoints(),
                            range: model.selectedRange,
                            maxAccuracyM: thresholds.maxHorizontalAccuracyM,
                            highlight: model.visibleHighlight
                        )
                        EventsLaneView(
                            segments: model.windowSegments(),
                            range: model.selectedRange,
                            selectedID: model.selectedSegmentID,
                            onSelect: { model.selectAssumption(at: $0) }
                        )
                        detailPane
                    }
                }
            } else {
                Text("Open an export JSON (ShareLink session file from iPhone).")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                model.load(url: url)
            case .failure(let error):
                model.reportLoadFailure(error.localizedDescription)
            }
        }
        .onAppear(perform: autoLoadDebugExport)
    }

    private var toolbar: some View {
        HStack {
            Button("Open…") {
                isImporterPresented = true
            }
            .keyboardShortcut("o", modifiers: .command)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.sessionTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if model.package != nil {
                    Text("Session \(model.durationLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let segment = model.selectedSegment {
            VStack(alignment: .leading, spacing: 4) {
                Text("Selected assumption")
                    .font(.headline)
                HStack {
                    Text(segment.code)
                        .foregroundStyle(AssumptionColors.color(for: segment.code))
                        .fontWeight(.semibold)
                    Text(segment.start.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(.secondary)
                    if let activity = segment.motionActivity {
                        Text("activity=\(activity)")
                            .foregroundStyle(.secondary)
                    }
                    if let water = segment.waterSubmersionState {
                        Text("water=\(water)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                Text(segment.reason)
                    .font(.body)
                    .textSelection(.enabled)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        } else {
            Text("Click assumption lane to inspect reason")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func autoLoadDebugExport() {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-loadExport"),
           args.index(after: index) < args.endIndex {
            model.loadPathAsync(args[args.index(after: index)])
            return
        }
        #if DEBUG
        // Hardcoded short session for crash reproduction (dev only).
        let hardcoded =
            "/Users/ducosebel/Development/rppl/Exports/0158167A-A54E-45D4-8245-3AAD743F7979.json"
        if FileManager.default.fileExists(atPath: hardcoded) {
            model.loadPathAsync(hardcoded)
        }
        #endif
    }
}
