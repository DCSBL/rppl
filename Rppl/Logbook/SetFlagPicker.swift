import RpplCore
import SwiftUI

extension SetFlagKind {
    var tint: Color {
        switch self {
        case .startFinish: Color.rpplMetricRiding
        case .trick: Color.rpplMetricLaps
        case .custom: Color.rpplMuted
        }
    }

    var title: String {
        switch self {
        case .startFinish: String(localized: "Start & finish")
        case .trick: String(localized: "Tricks")
        case .custom: String(localized: "Yours")
        }
    }
}

enum SetFlagLabels {
    /// Localized label for a preset code; any other flag is shown as typed.
    static func label(_ flag: String) -> String {
        switch flag {
        case "cable_stop": String(localized: "Cable stop")
        case "clean_exit": String(localized: "Clean exit")
        case "clean_start": String(localized: "Clean start")
        case "failed_start": String(localized: "Failed start")
        case "wipeout": String(localized: "Wipeout")
        case "failed_jump": String(localized: "Failed jump")
        case "new_trick": String(localized: "New trick")
        case "successful_jump": String(localized: "Successful jump")
        default: flag
        }
    }

    static func sorted(_ flags: [String]) -> [String] {
        flags.sorted { label($0).localizedCaseInsensitiveCompare(label($1)) == .orderedAscending }
    }
}

/// What a set card needs to show and change its flags.
struct SetFlagging {
    var selected: [String]
    var customs: [String]
    var toggle: (String) -> Void
    var addCustom: (String) -> Void
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
        return SetFlagLabels.sorted(flagging.customs + extra).filter { seen.insert($0.lowercased()).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach([SetFlagKind.startFinish, .trick], id: \.self) { kind in
                group(kind, flags: SetFlagLabels.sorted(SetFlags.presets(of: kind)))
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

/// Medium sheet around the cloud. Changes apply to the caller's draft as they are tapped.
struct SetFlagSheet: View {
    let title: String
    let flagging: SetFlagging
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                SetFlagCloud(flagging: flagging)
                    .padding(20)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A set card's flag row: its badges (tap removes) and a trailing "+ Flag".
struct SetFlagRow: View {
    let title: String
    let flagging: SetFlagging
    @State private var showsPicker = false

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(flagging.selected, id: \.self) { flag in
                SetFlagBadge(flag: flag) { flagging.toggle(flag) }
            }
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
        .sheet(isPresented: $showsPicker) { SetFlagSheet(title: title, flagging: flagging) }
    }
}

/// Phone-local persistence for flag drafts and the custom label list.
enum SetFlagStorage {
    private static func draftKey(_ sessionId: String) -> String { "rppl.setFlagDraft.\(sessionId)" }
    private static let customsKey = "rppl.customSetFlags"

    static func loadDraft(sessionId: String) -> [String: [String]]? {
        guard let data = UserDefaults.standard.data(forKey: draftKey(sessionId)) else { return nil }
        return try? JSONDecoder().decode([String: [String]].self, from: data)
    }

    static func saveDraft(_ draft: [String: [String]], sessionId: String) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: draftKey(sessionId))
    }

    static func clearDraft(sessionId: String) {
        UserDefaults.standard.removeObject(forKey: draftKey(sessionId))
    }

    static func loadCustoms() -> [String] {
        UserDefaults.standard.stringArray(forKey: customsKey) ?? []
    }

    static func saveCustoms(_ customs: [String]) {
        UserDefaults.standard.set(customs, forKey: customsKey)
    }
}
