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
        TabView(selection: $page) {
            ForEach(ActivityCodes.pickerCodes, id: \.self) { code in
                ActivityStartPage(
                    code: code,
                    isStarting: session.isStarting && session.startingActivityCode == code,
                    enabled: canStart
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
