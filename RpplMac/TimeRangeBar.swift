import AppKit
import SwiftUI

struct TimeRangeBar: View {
    @Bindable var model: SessionAnalysisModel

    var body: some View {
        if let span = model.sessionSpan {
            let startBound = span.lowerBound.timeIntervalSinceReferenceDate
            let endBound = span.upperBound.timeIntervalSinceReferenceDate
            let spanSeconds = endBound - startBound

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Window")
                        .font(.headline)
                    Spacer()
                    Text(model.windowDurationLabel)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                if spanSeconds >= SessionAnalysisModel.minimumWindow {
                    labeledSlider(
                        title: "Start",
                        value: model.rangeStart.timeIntervalSinceReferenceDate,
                        bounds: startBound...(endBound - SessionAnalysisModel.minimumWindow)
                    ) { model.setRangeStart(Date(timeIntervalSinceReferenceDate: $0)) }

                    labeledSlider(
                        title: "End",
                        value: model.rangeEnd.timeIntervalSinceReferenceDate,
                        bounds: (startBound + SessionAnalysisModel.minimumWindow)...endBound
                    ) { model.setRangeEnd(Date(timeIntervalSinceReferenceDate: $0)) }
                }

                Text(timeCaption(span: span, spanSeconds: max(spanSeconds, 0)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func labeledSlider(
        title: String,
        value: Double,
        bounds: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        HStack {
            Text(title)
                .frame(width: 44, alignment: .leading)
            AppKitSlider(value: value, bounds: bounds, onChange: onChange)
                .frame(height: 22)
            Text(shortTime(Date(timeIntervalSinceReferenceDate: value)))
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)
        }
    }

    private func shortTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }

    private func timeCaption(span: ClosedRange<Date>, spanSeconds: TimeInterval) -> String {
        let startOffset = model.rangeStart.timeIntervalSince(span.lowerBound)
        let endOffset = model.rangeEnd.timeIntervalSince(span.lowerBound)
        return String(
            format: "Session %.0fs · selection %.0f–%.0fs",
            spanSeconds,
            startOffset,
            endOffset
        )
    }
}

/// AppKit slider — SwiftUI `Slider` hits RenderBox/Metal on Intel.
struct AppKitSlider: NSViewRepresentable {
    var value: Double
    var bounds: ClosedRange<Double>
    var onChange: (Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: bounds.lowerBound, maxValue: bounds.upperBound, target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.isContinuous = true
        context.coordinator.slider = slider
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.onChange = onChange
        slider.minValue = bounds.lowerBound
        slider.maxValue = bounds.upperBound
        if abs(slider.doubleValue - value) > 0.000_1 {
            slider.doubleValue = value
        }
    }

    final class Coordinator: NSObject {
        var onChange: (Double) -> Void
        weak var slider: NSSlider?

        init(onChange: @escaping (Double) -> Void) {
            self.onChange = onChange
        }

        @objc func changed(_ sender: NSSlider) {
            onChange(sender.doubleValue)
        }
    }
}
