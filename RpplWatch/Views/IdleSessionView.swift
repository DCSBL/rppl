import SwiftUI
import RpplCore

enum IdlePickerPage: Hashable {
    case activity(String)
    case sync
}

struct IdleSessionView: View {
    @Bindable var session: WatchSessionController
    @Bindable var transfer: WatchTransferService
    @State private var page = IdlePickerPage.activity(ActivityCodes.pickerLandingCode())

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                ForEach(ActivityCodes.pickerCodes, id: \.self) { code in
                    ActivityStartPage(
                        code: code,
                        isStarting: session.isStarting && session.startingActivityCode == code,
                        enabled: canStart,
                        needsSetup: session.needsPermissionSetup
                    ) {
                        start(code)
                    }
                    .tag(IdlePickerPage.activity(code))
                    .allowsHitTesting(canStart)
                }

                IdleSyncPage(session: session, transfer: transfer)
                    .tag(IdlePickerPage.sync)
            }
            .tabViewStyle(.verticalPage)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        WatchLogbookListView()
                    } label: {
                        Image(systemName: "book.fill")
                    }
                    .accessibilityLabel(String(localized: "Logbook"))
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $session.isShowingPermissionChecklist) {
            StartPermissionsView(session: session)
        }
    }

    private var canStart: Bool {
        !session.isStarting && !session.isStopping && !session.isRunning
    }

    private func start(_ code: String) {
        WakeLog.debug(.ui, "tap start activity=\(code)")
        page = .activity(code)
        Task { await session.startSession(activityCode: code) }
    }
}
