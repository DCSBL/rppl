import RpplCore
import SwiftUI

extension SetFlagKind {
    var tint: Color {
        switch self {
        case .start: Color.rpplMetricRiding
        case .exit: Color.rpplMetricSpeed
        case .trick: Color.rpplMetricLaps
        case .custom: Color.rpplMuted
        }
    }

    var title: String {
        switch self {
        case .start: String(localized: "Start")
        case .exit: String(localized: "Exit")
        case .trick: String(localized: "Tricks")
        case .custom: String(localized: "Yours")
        }
    }
}

enum SetFlagLabels {
    /// Localized label for a preset code; any other flag is shown as typed.
    static func label(_ flag: String) -> String {
        switch flag {
        case "clean_start": String(localized: "Clean start")
        case "failed_start": String(localized: "Failed start")
        case "jump_start": String(localized: "Jumpstart")
        case "nollie_start": String(localized: "Nollie start")
        case "other_start": String(localized: "Other start")
        case "sit_start": String(localized: "Sit start")
        case "slide_start": String(localized: "Slide start")
        case "cable_snap": String(localized: "Cable snap")
        case "cable_stopped": String(localized: "Cable stopped")
        case "clean_exit": String(localized: "Clean exit")
        case "dry_exit": String(localized: "Dry exit")
        case "fall": String(localized: "Fall")
        case "wipeout": String(localized: "Wipeout")
        case "180": "180"
        case "360": "360"
        case "backroll": String(localized: "Backroll")
        case "box": String(localized: "Box")
        case "failed_jump": String(localized: "Failed jump")
        case "frontroll": String(localized: "Frontroll")
        case "kicker": String(localized: "Kicker")
        case "new_trick": String(localized: "New trick")
        case "ollie": String(localized: "Ollie")
        case "rail": String(localized: "Rail")
        case "raley": String(localized: "Raley")
        case "switch": String(localized: "Switch")
        case "tantrum": String(localized: "Tantrum")
        default: flag
        }
    }
}

/// What a set card needs to show and change its flags.
struct SetFlagging {
    var selected: [String]
    var customs: [String]
    var toggle: (String) -> Void
    var addCustom: (String) -> Void
    /// Removes the label from the saved list and from every set.
    var deleteCustom: (String) -> Void
}

/// One text-only badge: filled in its group color when selected, outlined when not.
struct SetFlagBadge: View {
    let flag: String
    var isSelected = true
    var action: (() -> Void)?

    private var tint: Color { SetFlags.kind(of: flag).tint }

    var body: some View {
        if let action {
            Button(action: action) { badge }
                .buttonStyle(.borderless)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            badge
        }
    }

    private var badge: some View {
        Text(SetFlagLabels.label(flag))
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? Color.white : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? tint : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(tint, lineWidth: 1.5))
    }
}

/// Every flag as a wrapping cloud, grouped by kind, alphabetical inside a group. Tap toggles.
struct SetFlagCloud: View {
    let flagging: SetFlagging
    @State private var customText = ""

    private var customFlags: [String] {
        let extra = flagging.selected.filter { SetFlags.kind(of: $0) == .custom }
        var seen = Set<String>()
        return SetFlags.ordered(flagging.customs + extra, by: SetFlagLabels.label).filter { seen.insert($0.lowercased()).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach([SetFlagKind.start, .exit, .trick], id: \.self) { kind in
                group(kind, flags: SetFlags.ordered(SetFlags.presets(of: kind), by: SetFlagLabels.label))
            }
            group(.custom, flags: customFlags)
            HStack {
                TextField("Add custom…", text: $customText)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .onSubmit(addCustom)
                Button("Add", action: addCustom)
                    .disabled(SetFlags.normalized(custom: customText) == nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.rpplFill, in: Capsule())
        }
    }

    private func group(_ kind: SetFlagKind, flags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kind.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(kind.tint)
                .textCase(.uppercase)
            FlowLayout(spacing: 8) {
                ForEach(flags, id: \.self) { flag in
                    SetFlagBadge(
                        flag: flag,
                        isSelected: SetFlags.contains(flag, in: flagging.selected)
                    ) { flagging.toggle(flag) }
                        .contextMenu {
                            if kind == .custom {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    flagging.deleteCustom(flag)
                                }
                            }
                        }
                }
            }
        }
    }

    private func addCustom() {
        guard SetFlags.normalized(custom: customText) != nil else { return }
        flagging.addCustom(customText)
        customText = ""
    }
}

/// A set card's flag row. Read mode: the saved badges, nothing when empty. Edit mode (`flagging`
/// set): badges tap to remove, plus a trailing "+ Flag".
struct SetFlagRow: View {
    let title: String
    let flags: [String]
    var flagging: SetFlagging?
    @State private var showsPicker = false

    var body: some View {
        if flagging != nil || !flags.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(flags, id: \.self) { flag in
                    let remove: (() -> Void)? = flagging.map { editing in { editing.toggle(flag) } }
                    SetFlagBadge(flag: flag, action: remove)
                }
                if flagging != nil {
                    Button { showsPicker = true } label: {
                        Text("+ Flag")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.rpplMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .overlay(Capsule().strokeBorder(Color.rpplMuted.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                    }
                    .buttonStyle(.borderless)
                }
            }
            .sheet(isPresented: $showsPicker) {
                if let flagging {
                    NavigationStack {
                        ScrollView { SetFlagCloud(flagging: flagging).padding(20) }
                            .navigationTitle(title)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) { Button("Done") { showsPicker = false } }
                            }
                    }
                    .presentationDetents([.medium, .large])
                    .presentationBackground(Color.rpplBackground)
                }
            }
        }
    }
}

/// "🏁 Set x" heading shared by tracked and manual set cards.
struct SetCardTitle: View {
    let index: Int

    var body: some View {
        Label {
            Text("Set \(index)")
        } icon: {
            Image(systemName: MetricKind.sets.systemImage)
                .foregroundStyle(MetricKind.sets.tint)
        }
        .foregroundStyle(Color.rpplText)
        .font(.headline)
        .lineLimit(2)
        .minimumScaleFactor(0.75)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Manual sessions have no per-set data: just the heading and the flags.
struct ManualSetCard: View {
    let index: Int
    let flags: [String]
    var flagging: SetFlagging?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SetCardTitle(index: index)
            SetFlagRow(title: String(localized: "Set \(index) flags"), flags: flags, flagging: flagging)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rpplTileChrome()
    }
}
