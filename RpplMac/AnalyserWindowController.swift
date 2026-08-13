import AppKit
import UniformTypeIdentifiers
import RpplCore

@MainActor
final class AnalyserWindowController: NSWindowController, NSWindowDelegate {
    private let model = SessionAnalysisModel()
    private let root = AnalyserRootView()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Rppl Mac"
        window.center()
        self.init(window: window)
        window.delegate = self
        root.model = model
        root.onOpen = { [weak self] in self?.presentOpenPanel() }
        model.onChange = { [weak self] in
            guard let self else { return }
            self.root.reload(from: self.model)
        }
        window.contentView = root
    }

    func autoLoadDebugExportIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-loadExport"),
           args.index(after: index) < args.endIndex {
            model.loadPathAsync(args[args.index(after: index)])
            return
        }
        #if DEBUG
        let hardcoded =
            "/Users/ducosebel/Development/rppl/Exports/0158167A-A54E-45D4-8245-3AAD743F7979.json"
        if FileManager.default.fileExists(atPath: hardcoded) {
            model.loadPathAsync(hardcoded)
        }
        #endif
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.load(url: url)
    }
}

@MainActor
final class AnalyserRootView: NSView {
    var model: SessionAnalysisModel?
    var onOpen: (() -> Void)?

    private let openButton = NSButton(title: "Open…", target: nil, action: nil)
    private let titleLabel = NSTextField(labelWithString: "No session")
    private let statusLabel = NSTextField(labelWithString: "")
    private let startSlider = NSSlider()
    private let endSlider = NSSlider()
    private let startValueLabel = NSTextField(labelWithString: "")
    private let endValueLabel = NSTextField(labelWithString: "")
    private let windowLabel = NSTextField(labelWithString: "Window")
    private let mapPlot = PlotNSView()
    private let speedPlot = PlotNSView()
    private let accuracyPlot = PlotNSView()
    private let eventsPlot = PlotNSView()
    private let detailLabel = NSTextField(wrappingLabelWithString: "Click assumption lane to inspect reason")
    private let scroll = NSScrollView()
    private let stack = NSStackView()
    private let thresholds = AssumptionThresholds.default

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = false
        build()
    }

    private func build() {
        openButton.target = self
        openButton.action = #selector(openClicked)
        openButton.bezelStyle = .rounded

        titleLabel.font = .boldSystemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        windowLabel.font = .boldSystemFont(ofSize: 13)
        detailLabel.font = .systemFont(ofSize: 12)

        for slider in [startSlider, endSlider] {
            slider.target = self
            slider.action = #selector(sliderChanged(_:))
            slider.isContinuous = true
        }
        startValueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        endValueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)

        [mapPlot, speedPlot, accuracyPlot, eventsPlot].forEach { $0.wantsLayer = false }

        let toolbar = NSStackView(views: [openButton, titleLabel, statusLabel])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 8
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let startRow = labeled("Start", slider: startSlider, valueLabel: startValueLabel)
        let endRow = labeled("End", slider: endSlider, valueLabel: endValueLabel)

        for plot in [mapPlot, speedPlot, accuracyPlot, eventsPlot] {
            plot.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            mapPlot.heightAnchor.constraint(equalToConstant: 200),
            speedPlot.heightAnchor.constraint(equalToConstant: 140),
            accuracyPlot.heightAnchor.constraint(equalToConstant: 110),
            eventsPlot.heightAnchor.constraint(equalToConstant: 120)
        ])

        let plots = NSStackView(views: [
            section("GPS track", mapPlot),
            section("Speed (usable km/h)", speedPlot),
            section("GPS accuracy (m)", accuracyPlot),
            section("Assumptions / activity / water", eventsPlot),
            detailLabel
        ])
        plots.orientation = .vertical
        plots.alignment = .leading
        plots.spacing = 10

        let document = NSView(frame: .zero)
        document.wantsLayer = false
        plots.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(plots)
        NSLayoutConstraint.activate([
            plots.topAnchor.constraint(equalTo: document.topAnchor),
            plots.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            plots.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            plots.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            plots.widthAnchor.constraint(greaterThanOrEqualToConstant: 900)
        ])

        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.wantsLayer = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        [toolbar, windowLabel, startRow, endRow, scroll].forEach { stack.addArrangedSubview($0) }
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
            document.widthAnchor.constraint(equalTo: scroll.widthAnchor)
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(eventsClicked(_:)))
        eventsPlot.addGestureRecognizer(click)
    }

    private func labeled(_ title: String, slider: NSSlider, valueLabel: NSTextField) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        let row = NSStackView(views: [label, slider, valueLabel])
        row.orientation = .horizontal
        row.spacing = 8
        label.widthAnchor.constraint(equalToConstant: 44).isActive = true
        valueLabel.widthAnchor.constraint(equalToConstant: 70).isActive = true
        return row
    }

    private func section(_ title: String, _ plot: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: 12)
        let box = NSStackView(views: [label, plot])
        box.orientation = .vertical
        box.alignment = .leading
        box.spacing = 4
        plot.widthAnchor.constraint(equalTo: box.widthAnchor).isActive = true
        return box
    }

    @objc private func openClicked() {
        onOpen?()
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        guard let model else { return }
        let date = Date(timeIntervalSinceReferenceDate: sender.doubleValue)
        if sender === startSlider {
            model.setRangeStart(date)
        } else {
            model.setRangeEnd(date)
        }
    }

    @objc private func eventsClicked(_ gesture: NSClickGestureRecognizer) {
        guard let model else { return }
        let point = gesture.location(in: eventsPlot)
        let insetX: CGFloat = 36
        let plotWidth = max(eventsPlot.bounds.width - 44, 1)
        let clamped = min(max(point.x - insetX, 0), plotWidth)
        let t = Double(clamped / plotWidth)
        let range = model.selectedRange
        let date = range.lowerBound.addingTimeInterval(t * range.upperBound.timeIntervalSince(range.lowerBound))
        model.selectAssumption(at: date)
    }

    func reload(from model: SessionAnalysisModel) {
        self.model = model
        titleLabel.stringValue = model.sessionTitle
        if model.isLoading {
            statusLabel.stringValue = "Loading…"
            statusLabel.textColor = .secondaryLabelColor
        } else if let error = model.loadError {
            statusLabel.stringValue = error
            statusLabel.textColor = .systemRed
        } else if model.package != nil {
            statusLabel.stringValue = "Session \(model.durationLabel) · window \(model.windowDurationLabel)"
            statusLabel.textColor = .secondaryLabelColor
        } else {
            statusLabel.stringValue = "Open an export JSON"
            statusLabel.textColor = .secondaryLabelColor
        }

        if let span = model.sessionSpan {
            let startBound = span.lowerBound.timeIntervalSinceReferenceDate
            let endBound = span.upperBound.timeIntervalSinceReferenceDate
            startSlider.minValue = startBound
            startSlider.maxValue = max(endBound - SessionAnalysisModel.minimumWindow, startBound)
            endSlider.minValue = min(startBound + SessionAnalysisModel.minimumWindow, endBound)
            endSlider.maxValue = endBound
            startSlider.doubleValue = model.rangeStart.timeIntervalSinceReferenceDate
            endSlider.doubleValue = model.rangeEnd.timeIntervalSinceReferenceDate
            startValueLabel.stringValue = shortTime(model.rangeStart)
            endValueLabel.stringValue = shortTime(model.rangeEnd)
        }

        let locations = model.windowLocations()
        let speed = model.windowSpeedPoints()
        let accuracy = model.windowAccuracyPoints()
        let segments = model.windowSegments()
        let range = model.selectedRange
        let highlight = model.visibleHighlight
        let thresholds = self.thresholds
        let selectedID = model.selectedSegmentID

        mapPlot.drawHandler = { context, size in
            PlotDrawing.drawMap(context: context, size: size, locations: locations)
        }
        speedPlot.drawHandler = { context, size in
            PlotDrawing.drawSpeed(
                context: context,
                size: size,
                points: speed,
                range: range,
                thresholds: thresholds,
                highlight: highlight
            )
        }
        accuracyPlot.drawHandler = { context, size in
            PlotDrawing.drawAccuracy(
                context: context,
                size: size,
                points: accuracy,
                range: range,
                maxAccuracyM: thresholds.maxHorizontalAccuracyM,
                highlight: highlight
            )
        }
        eventsPlot.drawHandler = { context, size in
            PlotDrawing.drawEvents(
                context: context,
                size: size,
                segments: segments,
                range: range,
                selectedID: selectedID
            )
        }
        mapPlot.needsDisplay = true
        speedPlot.needsDisplay = true
        accuracyPlot.needsDisplay = true
        eventsPlot.needsDisplay = true

        if let segment = model.selectedSegment {
            var parts = [segment.code, shortTime(segment.start), segment.reason]
            if let activity = segment.motionActivity { parts.insert("activity=\(activity)", at: 2) }
            if let water = segment.waterSubmersionState { parts.insert("water=\(water)", at: 2) }
            detailLabel.stringValue = parts.joined(separator: " · ")
        } else {
            detailLabel.stringValue = "Click assumption lane to inspect reason"
        }
    }

    private func shortTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }
}
