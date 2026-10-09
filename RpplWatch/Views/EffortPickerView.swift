import SwiftUI

/// Effort bands as Fitness shows them: Easy 1-3, Moderate 4-6, Hard 7-8, All Out 9-10.
enum EffortBands {
    static let groupSizes = [3, 3, 2, 2]

    static func label(_ score: Int) -> String {
        switch score {
        case ...3: String(localized: "Easy")
        case 4...6: String(localized: "Moderate")
        case 7...8: String(localized: "Hard")
        default: String(localized: "All Out")
        }
    }

    static let tint = Color(red: 0.62, green: 0.38, blue: 0.92)
}

/// Glass pill on the session summary: "Add Effort" until rated, then the chosen effort.
struct EffortButton: View {
    /// 0 = not rated.
    @Binding var effort: Int
    @State private var isPickerPresented = false

    var body: some View {
        Button {
            if effort == 0 { effort = 5 }
            isPickerPresented = true
        } label: {
            HStack(spacing: 8) {
                if effort == 0 {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Effort")
                        .font(.headline)
                    Spacer(minLength: 0)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Effort")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        HStack(spacing: 8) {
                            Text("\(effort)")
                                .font(.footnote.weight(.semibold))
                                .frame(width: 24, height: 24)
                                .background(EffortBands.tint.opacity(0.35), in: Circle())
                            Text(EffortBands.label(effort))
                                .font(.headline)
                                .foregroundStyle(EffortBands.tint)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "plusminus")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .buttonStyle(.glass)
        .accessibilityValue(effort == 0 ? "" : "\(effort), \(EffortBands.label(effort))")
        .sheet(isPresented: $isPickerPresented) {
            EffortPickerView(effort: $effort)
        }
    }
}

/// Full-screen Digital Crown effort picker modelled on the Fitness one: four ramped groups of
/// 3/3/2/2 dots, the selected score as a white capsule, number and label underneath.
struct EffortPickerView: View {
    @Binding var effort: Int
    @Environment(\.dismiss) private var dismiss
    @State private var crown = 5.0

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                EffortBars(selection: effort) { effort = $0; crown = Double($0) }
                    .frame(maxHeight: .infinity)
                HStack(spacing: 8) {
                    Text("\(effort)")
                        .font(.headline)
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.3), in: Circle())
                    Text(EffortBands.label(effort))
                        .font(.title3.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 4)
            .containerBackground(
                LinearGradient(
                    colors: [Color(red: 0.55, green: 0.32, blue: 0.78), Color(red: 0.14, green: 0.04, blue: 0.28)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                for: .navigation
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .focusable()
        .digitalCrownRotation(
            $crown, from: 1, through: 10, by: 1,
            sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true
        )
        .onChange(of: crown) { _, new in effort = Int(new.rounded()) }
        .onAppear { crown = Double(max(1, effort)) }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: effort = min(10, effort + 1)
            case .decrement: effort = max(1, effort - 1)
            @unknown default: break
            }
            crown = Double(effort)
        }
    }
}

private struct EffortBars: View {
    let selection: Int
    let onSelect: (Int) -> Void

    private let gap: CGFloat = 4
    private let corner: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let sizes = EffortBands.groupSizes
            let total = CGFloat(sizes.reduce(0, +))
            let usable = proxy.size.width - gap * CGFloat(sizes.count - 1)
            let column = usable / total
            let height = proxy.size.height
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(sizes.enumerated()), id: \.offset) { index, size in
                    let first = sizes[..<index].reduce(0, +)
                    group(first: first, size: size, column: column, total: total, height: height)
                }
            }
        }
    }

    /// Ramp height (0...1 of the chart) at column position `t` (0...total).
    private func ramp(_ t: CGFloat, total: CGFloat, height: CGFloat) -> CGFloat {
        height * (0.28 + 0.70 * t / total)
    }

    private func group(first: Int, size: Int, column: CGFloat, total: CGFloat, height: CGFloat) -> some View {
        let width = column * CGFloat(size)
        let left = ramp(CGFloat(first), total: total, height: height)
        let right = ramp(CGFloat(first + size), total: total, height: height)
        return ZStack(alignment: .bottomLeading) {
            RampShape(leftHeight: left, rightHeight: right, corner: corner)
                .fill(.white.opacity(0.12))
                .frame(width: width, height: height)
            ForEach(0..<size, id: \.self) { i in
                let score = first + i + 1
                let centerT = CGFloat(first + i) + 0.5
                let capsuleHeight = ramp(centerT, total: total, height: height) - 6
                ZStack(alignment: .bottom) {
                    if score == selection {
                        Capsule()
                            .fill(.white)
                            .frame(width: column * 0.62, height: capsuleHeight)
                    } else {
                        Circle()
                            .fill(.white.opacity(0.35))
                            .frame(width: 4, height: 4)
                            .padding(.bottom, 10)
                    }
                }
                .frame(width: column, height: height, alignment: .bottom)
                .contentShape(Rectangle())
                .onTapGesture { onSelect(score) }
                .offset(x: column * CGFloat(i))
                .animation(.snappy(duration: 0.2), value: selection)
            }
        }
        .frame(width: width, height: height, alignment: .bottomLeading)
    }
}

/// Quadrilateral rising from `leftHeight` to `rightHeight`, with rounded corners.
private struct RampShape: Shape {
    let leftHeight: CGFloat
    let rightHeight: CGFloat
    let corner: CGFloat

    func path(in rect: CGRect) -> Path {
        // Inset polygon + round-join stroke = rounded corners without arc math.
        let r = corner
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.maxY - r))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY - leftHeight + r))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY - rightHeight + r))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY - r))
        path.closeSubpath()
        return path.strokedPath(StrokeStyle(lineWidth: r * 2, lineJoin: .round)).union(path)
    }
}

#Preview {
    @Previewable @State var effort = 7
    EffortPickerView(effort: $effort)
}
