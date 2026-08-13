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
                        value: Binding(
                            get: { model.rangeStart.timeIntervalSinceReferenceDate },
                            set: { model.setRangeStart(Date(timeIntervalSinceReferenceDate: $0)) }
                        ),
                        bounds: startBound...(endBound - SessionAnalysisModel.minimumWindow)
                    )

                    labeledSlider(
                        title: "End",
                        value: Binding(
                            get: { model.rangeEnd.timeIntervalSinceReferenceDate },
                            set: { model.setRangeEnd(Date(timeIntervalSinceReferenceDate: $0)) }
                        ),
                        bounds: (startBound + SessionAnalysisModel.minimumWindow)...endBound
                    )
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
        value: Binding<Double>,
        bounds: ClosedRange<Double>
    ) -> some View {
        HStack {
            Text(title)
                .frame(width: 44, alignment: .leading)
            Slider(value: value, in: bounds)
            Text(shortTime(Date(timeIntervalSinceReferenceDate: value.wrappedValue)))
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
