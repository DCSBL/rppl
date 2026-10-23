import SwiftUI

extension EnvironmentValues {
    /// Width of the free strip beside the app on iPhone Duo; 0 when the window has none.
    @Entry var sidebarWidth: CGFloat = 0
    /// Opens the Rppl settings modal.
    @Entry var openSettings: () -> Void = {}
}

struct SidebarAction: Identifiable {
    let id: String
    let label: LocalizedStringKey
    let systemImage: String
    var isActive = false
    let perform: () -> Void
}

/// What the screen on top wants in the sidebar. Screens register while they are visible; in a split
/// view several screens are visible at once, so the pieces merge, the newest screen winning.
@MainActor @Observable
final class SidebarModel {
    struct Items {
        /// Top of the strip, under the status icons (the add button).
        var primary: SidebarAction?
        /// Top of the strip; replaces the navigation buttons while a detail is open.
        var back: SidebarAction?
        /// Bottom of the strip, above the navigation buttons.
        var actions: [SidebarAction] = []
        /// Folded into one More menu after `actions`.
        var more: [SidebarAction] = []
    }

    private var registrations: [(owner: UUID, items: Items)] = []

    var items: Items {
        var merged = Items()
        for registration in registrations.reversed() {
            merged.primary = merged.primary ?? registration.items.primary
            merged.back = merged.back ?? registration.items.back
            if merged.actions.isEmpty { merged.actions = registration.items.actions }
            if merged.more.isEmpty { merged.more = registration.items.more }
        }
        return merged
    }

    func register(_ items: Items, for owner: UUID) {
        registrations.removeAll { $0.owner == owner }
        registrations.append((owner, items))
    }

    func unregister(_ owner: UUID) {
        registrations.removeAll { $0.owner == owner }
    }
}

private struct SidebarItemsModifier<Key: Hashable>: ViewModifier {
    @Environment(SidebarModel.self) private var model: SidebarModel?
    @State private var owner = UUID()
    let key: Key
    let items: SidebarModel.Items

    func body(content: Content) -> some View {
        content
            .onAppear { model?.register(items, for: owner) }
            .onChange(of: key) { _, _ in model?.register(items, for: owner) }
            .onDisappear { model?.unregister(owner) }
    }
}

extension View {
    /// Puts buttons in the Duo sidebar while this view is on screen. `key` changes whenever the
    /// actions do (for example a star turning on), so the sidebar picks up the new ones.
    func sidebarItems(
        key: some Hashable = 0,
        primary: SidebarAction? = nil,
        back: SidebarAction? = nil,
        actions: [SidebarAction] = [],
        more: [SidebarAction] = []
    ) -> some View {
        modifier(
            SidebarItemsModifier(
                key: key,
                items: SidebarModel.Items(primary: primary, back: back, actions: actions, more: more)
            )
        )
    }
}

/// The strip beside the app on iPhone Duo: add button on top, the navigation buttons floating at the
/// bottom, and the buttons of the open screen between them.
struct DuoSidebar: View {
    @Binding var selectedTab: AppTab
    let model: SidebarModel
    let topInset: CGFloat

    @Environment(\.openSettings) private var openSettings

    private static let tabs: [(tab: AppTab, title: LocalizedStringKey, systemImage: String)] = [
        (.logbook, "Logbook", "book.fill"),
        (.parks, "Parks", "mappin.and.ellipse"),
    ]

    var body: some View {
        let items = model.items
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                if let back = items.back {
                    iconButton(back)
                } else if let primary = items.primary {
                    iconButton(primary)
                }
                Spacer(minLength: 0)
                if !items.actions.isEmpty || !items.more.isEmpty {
                    actionsGroup(items)
                }
                if items.back == nil {
                    navigationGroup
                }
            }
        }
        .padding(.top, max(topInset, 44))
        .padding(.bottom, 12)
        .padding(.horizontal, 6)
        .frame(maxHeight: .infinity)
        .tint(Color.rpplAccent)
    }

    private func iconButton(_ action: SidebarAction) -> some View {
        Button(action: action.perform) {
            Image(systemName: action.systemImage)
                .font(.title3.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .tint(action.isActive ? Color.rpplAccent : nil)
        .accessibilityLabel(Text(action.label))
    }

    private func actionsGroup(_ items: SidebarModel.Items) -> some View {
        VStack(spacing: 12) {
            ForEach(items.actions) { iconButton($0) }
            if !items.more.isEmpty {
                Menu {
                    ForEach(items.more) { action in
                        Button(action: action.perform) {
                            Label(action.label, systemImage: action.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(Text("More"))
            }
        }
    }

    private var navigationGroup: some View {
        VStack(spacing: 4) {
            ForEach(Self.tabs, id: \.tab) { entry in
                let isSelected = selectedTab == entry.tab
                Button {
                    selectedTab = entry.tab
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: entry.systemImage)
                            .font(.title3)
                        Text(entry.title)
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(isSelected ? Color.rpplAccent : Color.rpplText)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isSelected ? Color.rpplAccent.opacity(0.18) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(Color.rpplText)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Settings"))
        }
        .padding(4)
        .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
    }
}
