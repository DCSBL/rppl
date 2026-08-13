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
                ProgressView("Loading export…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.package != nil {
                TimeRangeBar(model: model)
                // Map must not live inside ScrollView — layout loop / crash on macOS.
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
                ContentUnavailableView(
                    "Open an export JSON",
                    systemImage: "doc",
                    description: Text("ShareLink session file from iPhone.")
                )
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
        .onAppear(perform: loadLaunchArgumentIfPresent)
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

    private func loadLaunchArgumentIfPresent() {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-loadExport"),
              args.index(after: index) < args.endIndex else { return }
        let path = args[args.index(after: index)]
        do {
            try model.loadSynchronously(url: URL(fileURLWithPath: path))
        } catch {
            model.reportLoadFailure(error.localizedDescription)
        }
    }
}
