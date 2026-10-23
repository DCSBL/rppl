import SwiftUI
import UIKit
import UniformTypeIdentifiers
import RpplCore

enum AppTab: Hashable {
    case logbook
    case parks
}

struct ContentView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedTab: AppTab = .logbook
    @State private var logbookNavigation = LogbookNavigationRequest()
    @State private var openParkID: String?
    @State private var openFavorites = false
    @State private var openDebug = false
    @State private var showSettings = false
    @State private var safeInsets = EdgeInsets()
    @State private var sidebarModel = SidebarModel()
    @State private var iCloud = PhoneICloudDriveController.shared
    @State private var connectivity = PhoneConnectivityService.shared
    @State private var showICloudImport = false
    @State private var isManualICloudImport = false
    @State private var manualImportSummaries: [RemoteSessionSummary] = []
    @State private var showFileImporter = false
    @State private var isImporting = false
    @State private var showImportError = false
    @State private var importErrorText: String?
    @State private var showAlreadyImportedAlert = false
    @State private var pendingDuplicateSessionId: String?

    private var sidebarWidth: CGFloat {
        CGFloat(SidebarInset.width(leading: Double(safeInsets.leading), trailing: Double(safeInsets.trailing)))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Logbook", systemImage: "book.fill", value: AppTab.logbook) {
                LogbookView(navigation: $logbookNavigation)
                    .toolbarVisibility(sidebarWidth > 0 ? .hidden : .automatic, for: .tabBar)
            }

            Tab("Parks", systemImage: "mappin.and.ellipse", value: AppTab.parks) {
                ParksView(openParkID: $openParkID, openFavorites: $openFavorites)
                    .toolbarVisibility(sidebarWidth > 0 ? .hidden : .automatic, for: .tabBar)
            }
        }
        .environment(sidebarModel)
        .environment(\.sidebarWidth, sidebarWidth)
        .environment(\.openSettings, { showSettings = true })
        .background { RpplBackdrop() }
        .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { safeInsets = $0 }
        // The strip beside the app on iPhone Duo: the app's own colors run through it, the buttons sit on it.
        .overlay {
            if sidebarWidth > 0 {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    DuoSidebar(selectedTab: $selectedTab, model: sidebarModel, topInset: safeInsets.top)
                        .frame(width: sidebarWidth)
                }
                .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showSettings) {
            AppInfoView(
                showDebug: $openDebug,
                isImporting: isImporting,
                onImportSessionTapped: {
                    showSettings = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        presentManualImport()
                    }
                }
            )
            .presentationSizing(.form)
        }
        .tint(Color.rpplAccent)
        // Bug reports from a Duo or iPad say which layout was active; logs only when the layout changes.
        .onGeometryChange(for: WindowLayout.self) {
            WindowLayout.resolve(
                width: Double($0.size.width),
                isAccessibilityTextSize: dynamicTypeSize.isAccessibilitySize
            )
        } action: { layout in
            WakeLog.debug(.ui, "window layout=\(layout) textSize=\(dynamicTypeSize)")
        }
        .onOpenURL { url in
            if ParkDeepLink.isFavorites(url) {
                openFavorites = true
                selectedTab = .parks
            } else if let id = ParkDeepLink.parkID(from: url) {
                openParkID = id
                selectedTab = .parks
            } else if let id = SessionDeepLink.sessionID(from: url) {
                logbookNavigation.openSessionId = id
                selectedTab = .logbook
            } else if let tab = TabDeepLink(url: url) {
                switch tab {
                case .logbook: selectedTab = .logbook
                case .parks: selectedTab = .parks
                case .about: showSettings = true
                case .debug:
                    openDebug = true
                    showSettings = true
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $showICloudImport) {
            ICloudSessionImportView(
                summaries: isManualICloudImport
                    ? manualImportSummaries
                    : iCloud.pendingImportSummaries,
                iCloudImportEnabled: iCloud.isSyncEnabled && iCloud.isICloudAvailable,
                onImport: { ids in
                    showICloudImport = false
                    if isManualICloudImport {
                        isManualICloudImport = false
                    } else {
                        iCloud.dismissImportOffer()
                    }
                    Task {
                        await iCloud.importSelectedRemoteSessions(ids)
                    }
                },
                onCancel: {
                    showICloudImport = false
                    if isManualICloudImport {
                        isManualICloudImport = false
                    } else {
                        iCloud.dismissImportOffer()
                    }
                },
                onImportFromFile: {
                    showICloudImport = false
                    if isManualICloudImport {
                        isManualICloudImport = false
                    } else {
                        iCloud.dismissImportOffer()
                    }
                    showFileImporter = true
                }
            )
        }
        .onChange(of: iCloud.shouldOfferImport) { _, offer in
            // Auto-present only right after the user turns iCloud Drive sync on.
            // Any other trigger (e.g. deleting a workout) must stay silent —
            // the user reaches the picker via the manual Import button instead.
            guard offer, !iCloud.suppressImportOffer, iCloud.justEnabledSync else { return }
            iCloud.consumeJustEnabledSync()
            isManualICloudImport = false
            showICloudImport = true
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .alert(
            "Could not import session",
            isPresented: $showImportError,
            presenting: importErrorText
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .alert(
            "Already in logbook",
            isPresented: $showAlreadyImportedAlert
        ) {
            Button("Cancel", role: .cancel) {
                pendingDuplicateSessionId = nil
            }
            Button("Show") {
                if let sessionId = pendingDuplicateSessionId {
                    logbookNavigation.openSessionId = sessionId
                    logbookNavigation.highlightSessionId = sessionId
                    selectedTab = .logbook
                }
                pendingDuplicateSessionId = nil
            }
        } message: {
            Text("This session is already in your logbook.")
        }
    }

    private func presentManualImport() {
        manualImportSummaries = iCloud.summariesForManualImport()
        isManualICloudImport = true
        showICloudImport = true
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            presentImportFailure(SessionExportImportError.detail(for: error))
        case .success(let urls):
            guard let url = urls.first else { return }
            isImporting = true
            Task {
                do {
                    let importedId = try await connectivity.importExportedSession(from: url)
                    isImporting = false
                    logbookNavigation.openSessionId = importedId
                    logbookNavigation.highlightSessionId = importedId
                    selectedTab = .logbook
                } catch let error as SessionExportImportError {
                    isImporting = false
                    switch error {
                    case .alreadyImported(let sessionId):
                        pendingDuplicateSessionId = sessionId
                        showAlreadyImportedAlert = true
                    case .unreadable(let message):
                        presentImportFailure(message)
                    }
                } catch {
                    isImporting = false
                    presentImportFailure(SessionExportImportError.detail(for: error))
                    WakeLog.error(.transfer, "export-file import: \(error.localizedDescription)")
                }
            }
        }
    }

    private func presentImportFailure(_ message: String) {
        importErrorText = message
        Task { @MainActor in
            showImportError = true
        }
    }
}

#Preview {
    ContentView()
}
